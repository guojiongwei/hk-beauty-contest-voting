module Api
  module V1
    class VotesController < BaseController
      # 投票：需要登录，每个用户对同一候选人只能投一票
      def create
        candidate_id = params[:candidate_id].presence || params.dig(:vote, :candidate_id)

        # 候选人 ID 缺失属于参数问题，直接返回 422，避免 find(nil) 被当成 404
        if candidate_id.blank?
          return render json: { error: "请选择候选人" }, status: :unprocessable_entity
        end

        # 候选人不存在时会抛出 RecordNotFound，由全局异常处理返回 404
        candidate = Candidate.find(candidate_id)

        # 通过关联创建投票，user_id 由 current_user 自动带入，避免前端伪造
        vote = current_user.votes.new(candidate: candidate)

        if vote.save
          render json: {
            message: "投票成功",
            data: {
              id: vote.id,
              candidate_id: candidate.id,
              has_voted: true
            }
          }, status: :created
        else
          # 应用层唯一性校验失败：返回产品要求的中文提示
          error_message = if vote.errors.of_kind?(:user_id, :taken)
                            "您已经投过票了"
                          else
                            vote.errors.full_messages.first
                          end

          render json: { error: error_message }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotUnique
        # 数据库层兜底：并发请求同时通过应用层校验时，联合唯一索引会拒绝第二条写入
        render json: { error: "您已经投过票了" }, status: :unprocessable_entity
      end
    end
  end
end
