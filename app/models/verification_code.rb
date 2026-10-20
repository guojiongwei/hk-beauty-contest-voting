class VerificationCode < ApplicationRecord
  # 验证码用途：当前只支持注册
  PURPOSE_REGISTER = "register"
  PURPOSES = [PURPOSE_REGISTER].freeze

  # 验证码为 6 位数字
  CODE_LENGTH = 6
  # 有效期 5 分钟
  EXPIRES_IN = 5.minutes
  # 最多允许输错 5 次
  MAX_ATTEMPTS = 5
  # 同一手机号 60 秒内只能发送一次
  RESEND_INTERVAL = 60.seconds

  # 明文验证码只保存在内存中，用于发送短信，不落库
  attr_reader :plain_code

  before_validation :generate_code, on: :create
  before_validation :set_expires_at, on: :create

  validates :phone_number,
            presence: { message: "手机号不能为空" },
            format: { with: User::PHONE_NUMBER_REGEX, message: "手机号格式不正确" }

  validates :code_digest, presence: { message: "验证码不能为空" }

  validates :purpose,
            presence: { message: "验证码用途不能为空" },
            inclusion: { in: PURPOSES, message: "验证码用途不合法" }

  validates :expires_at, presence: { message: "过期时间不能为空" }

  validates :attempts,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # 业务异常：验证码发送过于频繁、验证码错误、已过期等
  class VerificationError < StandardError; end

  # 发送验证码：先检查 60 秒限流，再生成一条新记录
  def self.issue!(phone_number:, purpose: PURPOSE_REGISTER)
    latest = where(phone_number: phone_number, purpose: purpose).order(created_at: :desc).first

    if latest.present? && latest.created_at > RESEND_INTERVAL.ago
      raise VerificationError, "验证码发送过于频繁，请稍后再试"
    end

    create!(phone_number: phone_number, purpose: purpose)
  end

  # 校验验证码：
  # 1. 取该手机号、该用途下最新的一条验证码；
  # 2. 依次判断是否存在、是否已使用/过期、错误次数；
  # 3. 比对成功后不立即标记使用，由调用方在业务成功后调用 consume!，
  #    这样注册失败时验证码仍可继续使用。
  def self.verify!(phone_number:, code:, purpose: PURPOSE_REGISTER)
    record = where(phone_number: phone_number, purpose: purpose).order(created_at: :desc).first

    raise VerificationError, "请先获取验证码" if record.nil?
    raise VerificationError, "验证码已使用或已过期，请重新获取" if record.used? || record.expired?

    if record.attempts >= MAX_ATTEMPTS
      raise VerificationError, "验证码错误次数过多，请重新获取"
    end

    unless record.code_match?(code)
      # 输错一次就累加次数，达到上限后只能重新获取
      record.increment!(:attempts)
      raise VerificationError, "验证码错误"
    end

    record
  end

  # 比对明文验证码与 bcrypt 摘要
  def code_match?(input)
    return false if input.blank?

    BCrypt::Password.new(code_digest) == input.to_s
  rescue BCrypt::Errors::InvalidHash
    # 摘要格式异常时按校验失败处理，避免抛 500
    false
  end

  # 标记验证码已使用，保证一次性
  def consume!
    update!(used_at: Time.current)
  end

  def expired?
    expires_at <= Time.current
  end

  def used?
    used_at.present?
  end

  private

  # 生成 6 位数字验证码，并只保存 bcrypt 摘要
  def generate_code
    @plain_code = format("%0#{CODE_LENGTH}d", SecureRandom.random_number(10**CODE_LENGTH))
    self.code_digest = BCrypt::Password.create(@plain_code)
  end

  def set_expires_at
    self.expires_at ||= EXPIRES_IN.from_now
  end
end
