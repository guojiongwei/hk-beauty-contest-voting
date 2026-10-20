# 初始化数据：香港选美大赛候选人
# 说明：
# 1. 使用 find_or_initialize_by(name:)，可以重复执行而不会产生重复候选人；
# 2. 已有记录的简介会被更新为这里的最新文案，便于后期调整；
# 3. photo_url 留空时前端会自动展示姓名首字作为占位，不会出现破图；
#    后续拿到真实照片地址后，直接改这里再执行一次 db:seed 即可。
candidates = [
  {
    name: "陈嘉琳",
    description: "25 岁，身高 172cm，毕业于香港中文大学。热爱芭蕾与古典钢琴，希望以优雅与自信传递香港女性的多元魅力。",
    photo_url: nil
  },
  {
    name: "李咏恩",
    description: "23 岁，身高 168cm，现职市场策划。擅长拉丁舞与潜水，相信美丽源于健康的生活方式与从容的心态。",
    photo_url: nil
  },
  {
    name: "黄心怡",
    description: "26 岁，身高 175cm，硕士在读。长期参与社区志愿服务，希望用影响力推动儿童教育与环保议题。",
    photo_url: nil
  },
  {
    name: "何乐儿",
    description: "22 岁，身高 170cm，大学应届毕业生。精通普通话、粤语与英语，热爱话剧表演与短片创作。",
    photo_url: nil
  },
  {
    name: "林焯妍",
    description: "24 岁，身高 173cm，健身教练兼营养师。坚持科学训练与均衡饮食，鼓励更多女性拥抱力量之美。",
    photo_url: nil
  },
  {
    name: "吴卓颖",
    description: "27 岁，身高 169cm，律师。业余时间担任青少年辩论导师，希望以专业与温度诠释现代女性的力量。",
    photo_url: nil
  },
  {
    name: "邓凯晴",
    description: "21 岁，身高 171cm，音乐学院学生。主修声乐，曾参与多场慈善演出，梦想用歌声连接更多人心。",
    photo_url: nil
  },
  {
    name: "苏颖桐",
    description: "25 岁，身高 166cm，平面设计师。热衷岭南文化保育，希望把传统元素带进当代时尚表达。",
    photo_url: nil
  }
]

# 逐条写入：存在则更新简介，不存在则新建
candidates.each do |attributes|
  candidate = Candidate.find_or_initialize_by(name: attributes[:name])
  candidate.description = attributes[:description]
  # 只有提供了照片地址才覆盖，避免重复执行时把已有照片清空
  candidate.photo_url = attributes[:photo_url] if attributes[:photo_url].present?
  candidate.save!
end

puts "[seeds] 候选人数据准备完成，当前共 #{Candidate.count} 位候选人"
