class CreateVotes < ActiveRecord::Migration[7.1]
  def change
    create_table :votes do |t|
      # 投票用户：用户删除时级联删除其投票记录
      t.references :user, null: false, foreign_key: true
      # 被投候选人：候选人删除时级联删除相关投票记录
      t.references :candidate, null: false, foreign_key: true

      t.timestamps
    end

    # 核心防刷票：联合唯一索引，保证同一用户对同一候选人只能投一票
    # 即使应用层校验被绕过，数据库层依然会拒绝重复写入
    add_index :votes, [:user_id, :candidate_id], unique: true
  end
end
