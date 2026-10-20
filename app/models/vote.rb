class Vote < ApplicationRecord
  # 每条投票必须归属于一个用户和一个候选人
  belongs_to :user
  belongs_to :candidate

  # 应用层防重复投票：同一用户对同一候选人只能投一次
  # 数据库层还有 [:user_id, :candidate_id] 联合唯一索引作为最终防线
  validates :user_id,
            uniqueness: { scope: :candidate_id, message: "您已经投过票了" }
end
