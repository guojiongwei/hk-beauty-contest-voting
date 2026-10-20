module Api
  module V1
    class BaseController < ApplicationController
      # 所有继承本控制器的接口默认都需要登录
      before_action :authenticate_user!

      # JWT 签名算法
      JWT_ALGORITHM = "HS256"
      # Token 有效期：24 小时
      JWT_EXPIRATION = 24.hours
      # 签名密钥：生产环境必须通过 JWT_SECRET 环境变量注入
      JWT_SECRET = ENV.fetch("JWT_SECRET", "hk-beauty-contest-voting-development-secret")

      private

      # 生成 JWT：payload 中写入 user_id，并附加签发时间与过期时间
      def encode_token(payload)
        payload = payload.dup
        payload[:iat] = Time.current.to_i
        payload[:exp] = JWT_EXPIRATION.from_now.to_i

        JWT.encode(payload, JWT_SECRET, JWT_ALGORITHM)
      end

      # 解析请求头中的 Token
      # 约定格式：Authorization: Bearer <token>
      def decoded_token
        authorization = request.headers["Authorization"]
        return nil if authorization.blank?

        # 兼容只传 token、不带 Bearer 前缀的写法
        token = authorization.to_s.split(" ").last
        return nil if token.blank?

        # 第三个参数 true 表示校验签名，algorithm 防止算法混淆攻击
        decoded, = JWT.decode(token, JWT_SECRET, true, algorithm: JWT_ALGORITHM)
        decoded
      rescue JWT::ExpiredSignature, JWT::DecodeError
        # Token 过期或非法时统一返回 nil，由 authenticate_user! 处理成 401
        nil
      end

      # 当前登录用户：通过 Token 中的 user_id 查询
      # 使用 defined? 做记忆化，避免同一请求内重复解析 Token 与查库
      def current_user
        return @current_user if defined?(@current_user)

        payload = decoded_token
        @current_user = payload.present? ? User.find_by(id: payload["user_id"]) : nil
      end

      # 登录拦截器：未登录或 Token 失效时返回 401
      def authenticate_user!
        return if current_user.present?

        render json: { error: "请先登录或登录状态已过期" }, status: :unauthorized
      end
    end
  end
end
