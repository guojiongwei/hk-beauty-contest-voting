module Api
  module V1
    class UsersController < ApplicationController
      # 关闭 Rails 的参数自动包装，避免 JSON 被额外包一层 user
      # 这样扁平参数与嵌套参数都能按预期解析
      wrap_parameters false

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

        # 密码必填校验：提前返回中文提示，避免暴露 Rails 默认英文文案
        if attributes[:password].blank?
          return render json: { error: "密码不能为空" }, status: :unprocessable_entity
        end

        # 两次密码不一致时提前拦截，保证错误文案与接口文档一致
        if attributes[:password_confirmation].present? &&
           attributes[:password] != attributes[:password_confirmation]
          return render json: { error: "两次输入的密码不一致" }, status: :unprocessable_entity
        end

        user = User.new(attributes)

        if user.save
          render json: {
            message: "注册成功",
            data: user_json(user)
          }, status: :created
        else
          # 只取错误文案，去掉 Rails 默认拼接的英文属性名前缀
          render json: { error: user.errors.map(&:message).first }, status: :unprocessable_entity
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
