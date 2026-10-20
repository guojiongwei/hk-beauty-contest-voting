module Api
  module V1
    class VerificationCodesController < ApplicationController
      # 关闭参数自动包装，保持请求体为扁平结构
      wrap_parameters false

      # 发送注册验证码
      def create
        phone_number = params[:phone_number].to_s.strip

        # 入库前先做手机号格式校验，避免产生无效验证码记录
        unless phone_number.match?(User::PHONE_NUMBER_REGEX)
          return render json: { error: "手机号格式不正确" }, status: :unprocessable_entity
        end

        verification_code = VerificationCode.issue!(phone_number: phone_number)

        # 当前用日志模拟短信发送，生产环境替换为短信服务商 SDK
        Rails.logger.info(
          "[SMS] 向 #{phone_number} 发送注册验证码：#{verification_code.plain_code}"
        )

        data = {
          phone_number: phone_number,
          expires_in: VerificationCode::EXPIRES_IN.to_i
        }
        # 仅开发环境返回明文验证码，方便本地联调；生产环境绝不返回
        data[:debug_code] = verification_code.plain_code if Rails.env.development?

        render json: { message: "验证码已发送", data: data }, status: :created
      rescue VerificationCode::VerificationError => e
        # 60 秒内重复发送，按限流语义返回 429
        render json: { error: e.message }, status: :too_many_requests
      end
    end
  end
end
