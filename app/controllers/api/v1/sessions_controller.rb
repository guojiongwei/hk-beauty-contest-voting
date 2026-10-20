module Api
  module V1
    class SessionsController < BaseController
      # 关闭参数自动包装，保证 password 等非模型字段不会被包装层丢掉
      wrap_parameters false

      # 登录与登出都不需要携带有效 Token：
      # 登录时用户还没有 Token；登出时即使 Token 过期也应允许前端正常退出
      skip_before_action :authenticate_user!, only: [:create, :destroy]

      # 登录：支持手机号或用户名 + 密码
      def create
        credential = login_params[:phone_number].presence ||
                     login_params[:username].presence ||
                     login_params[:login].presence
        password = login_params[:password]

        # 基础参数校验，避免无意义的数据库查询
        if credential.blank? || password.blank?
          return render json: { error: "手机号/用户名和密码不能为空" }, status: :unprocessable_entity
        end

        # 先按手机号查，再按用户名查，兼容两种登录习惯
        user = User.find_by(phone_number: credential.to_s.strip) ||
               User.find_by(username: credential.to_s.strip)

        # authenticate 由 has_secure_password 提供，内部使用 bcrypt 比对密码
        if user&.authenticate(password)
          token = encode_token(user_id: user.id)

          render json: {
            message: "登录成功",
            token: token,
            user: user_json(user)
          }, status: :ok
        else
          # 不区分“用户不存在”和“密码错误”，避免账号枚举
          render json: { error: "手机号/用户名或密码错误" }, status: :unauthorized
        end
      end

      # 登出：JWT 无状态，后端不保存 Token，直接返回成功由前端清除本地 Token
      def destroy
        render json: { message: "登出成功" }, status: :ok
      end

      private

      # 兼容嵌套与扁平两种登录参数格式
      def login_params
        source = params[:user].present? ? params.require(:user) : params
        source.permit(:phone_number, :username, :login, :password)
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
