module Api
  module V1
    class CandidatesController < BaseController
      # 候选人列表：需要登录，返回当前用户是否已给该候选人投过票
      def index
        candidates = Candidate.order(id: :asc)

        # 核心优化：一次性查出当前用户投过的所有候选人 ID，避免在循环中逐条查询（N+1）
        voted_ids = current_user.votes.pluck(:candidate_id)

        render json: {
          data: candidates.map { |candidate| candidate_json(candidate, voted_ids) }
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
