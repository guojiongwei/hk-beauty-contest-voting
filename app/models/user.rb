class User < ApplicationRecord
  # 使用 bcrypt 对密码做摘要，自动提供 authenticate 方法
  has_secure_password

  # 用户删除时，其投票记录一并删除，避免产生脏数据
  has_many :votes, dependent: :destroy
  # 通过投票关联到候选人，便于查询“我投过哪些人”
  has_many :candidates, through: :votes

  # 简单的手机号格式：1 开头，第二位 3-9，共 11 位数字
  PHONE_NUMBER_REGEX = /\A1[3-9]\d{9}\z/

  # 用户名必填且唯一
  validates :username,
            presence: { message: "用户名不能为空" },
            uniqueness: { message: "用户名已被占用" },
            length: { maximum: 50, message: "用户名长度不能超过 50 个字符" }

  # 手机号必填、格式正确且唯一
  validates :phone_number,
            presence: { message: "手机号不能为空" },
            uniqueness: { message: "手机号已被注册" },
            format: { with: PHONE_NUMBER_REGEX, message: "手机号格式不正确" }

  # 密码长度限制；allow_nil 用于更新用户资料时不强制重新输入密码
  validates :password,
            length: { minimum: 6, message: "密码长度不能少于 6 位" },
            allow_nil: true
end
