class CreateVerificationCodes < ActiveRecord::Migration[7.1]
  def change
    create_table :verification_codes do |t|
      # 接收验证码的手机号，长度限制为 20，足够覆盖国际号码
      t.string :phone_number, null: false, limit: 20
      # 验证码摘要：使用 bcrypt 加密后存储，禁止明文落库
      t.string :code_digest, null: false, limit: 100
      # 验证码用途：当前仅用于注册，后续可扩展登录、找回密码等场景
      t.string :purpose, null: false, default: "register", limit: 20
      # 过期时间：验证码默认 5 分钟有效
      t.datetime :expires_at, null: false
      # 使用时间：为空表示尚未使用，使用后写入时间，保证验证码一次性
      t.datetime :used_at
      # 错误尝试次数：超过上限后要求重新获取，防止暴力枚举
      t.integer :attempts, null: false, default: 0

      t.timestamps
    end

    # 查询某手机号某用途的最新验证码时命中该联合索引
    add_index :verification_codes,
              [:phone_number, :purpose, :created_at],
              name: "index_verification_codes_on_phone_purpose_created"

    # 便于定时任务按过期时间清理历史验证码
    add_index :verification_codes, :expires_at
  end
end
