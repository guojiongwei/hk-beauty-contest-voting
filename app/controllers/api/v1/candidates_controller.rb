module Api
  module V1
    class CandidatesController < BaseController
      # 分页默认值与上限，防止一次请求拉取过多数据
      DEFAULT_PER_PAGE = 10
      MAX_PER_PAGE = 50

      # 候选人列表：需要登录，返回当前用户是否已给该候选人投过票
      def index
        # 计算安全的页码与每页条数
        page, per_page = pagination_params

        # 先统计总数，用于生成分页元信息
        total_count = Candidate.count
        total_pages = (total_count.to_f / per_page).ceil

        # 按主键排序，保证翻页结果稳定；limit + offset 适合数据量中等的候选人列表
        candidates = Candidate.order(id: :asc)
                              .limit(per_page)
                              .offset((page - 1) * per_page)

        # 核心优化：一次性查出当前用户投过的所有候选人 ID，避免在循环中逐条查询（N+1）
        voted_ids = current_user.votes.pluck(:candidate_id)

        render json: {
          data: candidates.map { |candidate| candidate_json(candidate, voted_ids) },
          meta: {
            current_page: page,
            per_page: per_page,
            total_count: total_count,
            total_pages: total_pages,
            has_next: page < total_pages,
            has_prev: page > 1
          }
        }, status: :ok
      end

      # 候选人详情：同样返回 has_voted 字段
      def show
        candidate = Candidate.find(params[:id])

        # 只取当前候选人这一条投票记录，仍然使用 pluck 后 include? 的统一写法
        voted_ids = current_user.votes.where(candidate_id: candidate.id).pluck(:candidate_id)

        render json: {
          data: candidate_json(candidate, voted_ids)
        }, status: :ok
      end

      private

      # 解析分页参数：
      # 1. 非数字、0、负数统一回退到第 1 页；
      # 2. per_page 限制在 1..MAX_PER_PAGE，防止被恶意放大。
      def pagination_params
        page = params[:page].to_i
        page = 1 if page < 1

        per_page = params[:per_page].to_i
        per_page = DEFAULT_PER_PAGE if per_page < 1
        per_page = MAX_PER_PAGE if per_page > MAX_PER_PAGE

        [page, per_page]
      end

      # 统一的候选人序列化，避免暴露多余字段
      # has_voted 由 Ruby 内存中的数组判断，不再触发额外 SQL
      def candidate_json(candidate, voted_ids)
        {
          id: candidate.id,
          name: candidate.name,
          description: candidate.description,
          photo_url: candidate.photo_url,
          has_voted: voted_ids.include?(candidate.id),
          created_at: candidate.created_at
        }
      end
    end
  end
end
