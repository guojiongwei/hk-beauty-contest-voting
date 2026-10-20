# JWT 白名单存储
# 设计考量：
# 1. JWT 本身无状态，签发后无法撤回。把 jti 写入 Redis 后，服务端就有了“是否仍有效”的判定依据；
# 2. 键格式为 jwt:token:<jti>，值为 user_id，TTL 与 Token 过期时间一致，过期后由 Redis 自动清理；
# 3. 登出时删除对应 jti 即可让该 Token 立即失效，其他设备签发的 Token 不受影响。
class TokenStore
  # 统一的键前缀，便于在 Redis 中区分业务数据与其他应用的数据
  KEY_PREFIX = "jwt:token:"

  class << self
    # Redis 客户端：进程内复用同一个连接
    # redis 5.x 的客户端自带连接互斥锁，可被 Puma 多线程安全共享
    def redis
      @redis ||= Redis.new(
        url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"),
        timeout: 1.0,
        reconnect_attempts: 1
      )
    end

    # 登录成功时写入白名单
    # ttl 必须为正整数，否则 setex 会直接报错
    def store(jti:, user_id:, ttl:)
      redis.setex(key(jti), ttl.to_i, user_id.to_i)
    end

    # 校验 Token 是否仍在白名单中
    # 同时比对 user_id，防止出现键存在但归属不一致的异常数据
    def valid?(jti:, user_id:)
      value = redis.get(key(jti))
      value.present? && value.to_i == user_id.to_i
    end

    # 登出：删除白名单记录，Token 立即失效
    def revoke(jti)
      redis.del(key(jti))
    end

    # 统一的键拼装，避免各处手写字符串导致前缀不一致
    def key(jti)
      "#{KEY_PREFIX}#{jti}"
    end
  end
end
