# JWT 签发与校验的统一入口
# 说明：
# 1. 登录、中间件、登出都只依赖本类，避免签名算法或密钥散落在多个文件；
# 2. payload 中固定携带 user_id 与 jti：
#    - user_id 用于还原当前用户；
#    - jti 是每条 Token 的唯一编号，Redis 以此为键保存白名单。
class JsonWebToken
  # 签名算法：HS256，解码时显式指定，防止算法混淆攻击
  ALGORITHM = "HS256"
  # Token 有效期：24 小时
  EXPIRATION = 24.hours

  class << self
    # 签发 Token
    # payload 只需传业务字段（user_id、jti），签发时间与过期时间在这里统一补齐
    def encode(payload, expires_at: EXPIRATION.from_now)
      payload = payload.dup
      payload[:iat] = Time.current.to_i
      payload[:exp] = expires_at.to_i

      JWT.encode(payload, secret, ALGORITHM)
    end

    # 解析 Token：签名错误、过期、格式非法都会抛出 JWT 异常
    # 由调用方（中间件）决定如何转换成 HTTP 响应，这里只负责密码学校验
    def decode(token)
      decoded, = JWT.decode(token, secret, true, algorithm: ALGORITHM)
      decoded
    end

    # 签名密钥：生产环境必须通过 JWT_SECRET 环境变量注入
    # 这里使用方法而不是常量，方便测试或运行时替换环境变量
    def secret
      ENV.fetch("JWT_SECRET", "hk-beauty-contest-voting-development-secret")
    end
  end
end
