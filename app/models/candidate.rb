class Candidate < ApplicationRecord
  # 候选人删除时，相关投票记录一并删除
  has_many :votes, dependent: :destroy

  # 候选人姓名必填，避免出现空白候选人
  validates :name,
            presence: { message: "候选人姓名不能为空" },
            length: { maximum: 100, message: "候选人姓名长度不能超过 100 个字符" }
end
