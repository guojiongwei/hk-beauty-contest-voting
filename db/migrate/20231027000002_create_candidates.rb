class CreateCandidates < ActiveRecord::Migration[7.1]
  def change
    create_table :candidates do |t|
      # 候选人姓名
      t.string :name, null: false
      # 候选人简介，长度不固定使用 text
      t.text :description
      # 候选人照片地址，由前端或运营侧提供
      t.string :photo_url

      t.timestamps
    end
  end
end
