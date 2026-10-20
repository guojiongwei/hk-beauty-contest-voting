module Api
  module V1
    class UsersController < ApplicationController
      # 注册接口：无需登录
      def create
        # 统一去除用户名与手机号两端的空格，避免“看起来唯一”实际不唯一
        attributes = user_params.to_h.symbolize_keys
        attributes[:username] = attributes[:username].to_s.strip
        attributes[:phone_number] = attributes[:phone_number].to_s.strip

        # 手机号格式校验：与 User 模型保持同一套正则
        unless attributes[:phone_number].match?(User::PHONE_NUMBER_REGEX)
          return render json: { error: "手机号格式不正确" }, status: :unprocessable_entity
        end

        user = User.new(attributes)

        if user.save
          render json: {
            message: "注册成功",
            data: user_json(user)
          }, status: :created
        else
          # 返回第一条校验错误，例如用户名已存在、密码过短
          render json: { error: user.errors.full_messages.first }, status: :unprocessable_entity
        end
      end

      private

      # 兼容两种请求体：
      # 1. { "user": { "username": "...", ... } }
      # 2. { "username": "...", ... }
      def user_params
        source = params[:user].present? ? params.require(:user) : params
        source.permit(:username, :phone_number, :password, :password_confirmation)
      end

      # 只暴露必要字段，绝不返回 password_digest
      def user_json(user)
        {
          id: user.id,
          username: user.username,
          phone_number: user.phone_number,
          created_at: user.created_at
        }
      end
    end
  end
end
