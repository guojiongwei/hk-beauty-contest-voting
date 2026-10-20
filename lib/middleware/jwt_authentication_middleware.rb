# JWT 认证中间件
# 职责：
# 1. 从 Authorization 请求头提取 Token；
# 2. 校验签名与过期时间（JsonWebToken.decode）；
# 3. 校验 Token 是否仍在 Redis 白名单中（TokenStore.valid?）；
# 4. 把 user_id、payload、原始 Token 写入 Rack env，供控制器直接读取。
#
# 设计考量：
# - 中间件只做“解析与校验”，不直接渲染响应。是否要求登录由控制器决定，
#   这样登录、发送验证码等公开接口即使携带了过期 Token 也不会被误拦截；
# - 校验失败时把原因写入 env["jwt_error"]，控制器统一转成 401/503，
#   避免每个接口重复解析 Token。
class JwtAuthenticationMiddleware
  # 标准格式：Authorization: Bearer <token>
  # 同时兼容不带 Bearer 前缀的写法，方便本地用 curl 调试
  BEARER_PATTERN = /\ABearer\s+(.+)\z/i

  # Token 已从 Redis 白名单删除（登出、被顶下线等）时抛出
  class TokenRevokedError < StandardError; end

  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)
    token = extract_token(request)

    # 没有携带 Token 时不做任何处理，交给控制器的 authenticate_user! 判断
    authenticate(env, token) if token.present?

    @app.call(env)
  end

  private

  # 从请求头提取 Token，格式非法时返回 nil
  def extract_token(request)
    authorization = request.headers["Authorization"].to_s.strip
    return nil if authorization.blank?

    match = authorization.match(BEARER_PATTERN)
    match ? match[1].strip : authorization
  end

  # 校验 Token 并写入当前用户信息
  def authenticate(env, token)
    payload = JsonWebToken.decode(token)
    user_id = payload["user_id"]
    jti = payload["jti"]

    # 老版本 Token 或伪造的 payload 可能缺少字段，直接按无效处理
    raise JWT::DecodeError, "Token 缺少必要信息" if user_id.blank? || jti.blank?

    # 即使签名合法，也必须存在于 Redis 白名单中，登出后的 Token 会在这里被拒绝
    raise TokenRevokedError unless TokenStore.valid?(jti: jti, user_id: user_id)

    env["current_user_id"] = user_id
    env["jwt_payload"] = payload
    env["current_token"] = token
  rescue JWT::ExpiredSignature
    # Token 过期：提示前端重新登录
    env["jwt_error"] = "登录状态已过期，请重新登录"
  rescue TokenRevokedError
    # 已登出或白名单被清理
    env["jwt_error"] = "登录状态已失效，请重新登录"
  rescue JWT::DecodeError
    # 签名错误、格式非法、缺少字段
    env["jwt_error"] = "登录凭证无效"
  rescue Redis::BaseError => e
    # Redis 不可用时不能放行，也不能伪装成“未登录”，单独返回 503 便于前端区分
    Rails.logger.error("[JWT] Redis 校验失败：#{e.class}: #{e.message}")
    env["jwt_error"] = "认证服务暂不可用，请稍后重试"
    env["jwt_error_status"] = 503
  end
end
