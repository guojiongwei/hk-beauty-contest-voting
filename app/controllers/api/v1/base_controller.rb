module Api
  module V1
    class BaseController < ApplicationController
      # 所有继承本控制器的接口默认都需要登录
      # Token 的解析与校验已由 JwtAuthenticationMiddleware 完成，这里只做登录状态判定
      before_action :authenticate_user!

      private

      # 当前登录用户：
      # user_id 由中间件写入 request.env，这里只负责查库并做请求内记忆化
      def current_user
        return @current_user if defined?(@current_user)

        user_id = request.env["current_user_id"]
        @current_user = user_id.present? ? User.find_by(id: user_id) : nil
      end

      # 登录拦截器：
      # - 中间件校验通过但用户已被删除时，env 中没有 jwt_error，按未登录处理；
      # - Token 过期、签名非法、已登出时，直接使用中间件写入的具体原因；
      # - Redis 不可用时，中间件会写入 503，避免把服务故障误报成未登录。
      def authenticate_user!
        return if current_user.present?

        render json: { error: request.env["jwt_error"] || "请先登录或登录状态已过期" },
               status: request.env["jwt_error_status"] || :unauthorized
      end
    end
  end
end
