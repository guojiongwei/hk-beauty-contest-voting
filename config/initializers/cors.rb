# 跨域配置：开发阶段允许所有来源访问，便于前端本地联调
# 生产环境请把 origins 收敛为具体域名，避免任意站点调用接口
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # 允许所有来源（包含 file:// 场景下的 Origin: null）
    origins "*"

    resource "*",
      headers: :any,
      # 明确暴露 Authorization，方便前端读取 Token 相关响应头
      expose: %w[Authorization],
      methods: [:get, :post, :put, :patch, :delete, :options, :head]
  end
end
