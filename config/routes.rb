Rails.application.routes.draw do
  # 健康检查：用于确认服务是否正常启动
  get "up" => "rails/health#show", as: :rails_health_check

  # API 路由统一使用 api/v1 命名空间，方便后续版本迭代
  namespace :api do
    namespace :v1 do
      # 用户注册
      resources :users, only: [:create]

      # 登录与登出
      resources :sessions, only: [:create] do
        collection do
          # 登出：JWT 为无状态令牌，后端无需存储，仅返回成功由前端清除 Token
          delete :current, to: "sessions#destroy"
        end
      end

      # 候选人列表与详情
      resources :candidates, only: [:index, :show]

      # 投票
      resources :votes, only: [:create]
    end
  end
end
