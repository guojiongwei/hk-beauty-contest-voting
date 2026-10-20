class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      # 用户名：登录展示与唯一标识之一
      t.string :username, null: false
      # 手机号：登录凭证之一，入库前会做格式校验
      t.string :phone_number, null: false
      # bcrypt 生成的密码摘要，绝不存储明文密码
      t.string :password_digest, null: false

      t.timestamps
    end

    # 唯一索引：数据库层保证用户名、手机号不可重复
    add_index :users, :username, unique: true
    add_index :users, :phone_number, unique: true
  end
end
