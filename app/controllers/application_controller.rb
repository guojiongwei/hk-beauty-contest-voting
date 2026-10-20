class ApplicationController < ActionController::API
  # 全局异常处理：先兜底 StandardError，再声明具体异常。
  # rescue_from 后声明的处理器优先级更高，因此具体异常放在兜底之后。
  rescue_from StandardError, with: :render_internal_server_error
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
  rescue_from ActiveRecord::RecordNotUnique, with: :render_record_not_unique
  rescue_from ActionController::ParameterMissing, with: :render_parameter_missing

  private

  # 404：资源不存在，统一返回 JSON，避免暴露 Rails 默认 HTML 页面
  def render_not_found(_exception)
    render json: { error: "资源不存在" }, status: :not_found
  end

  # 422：模型校验失败，返回第一条可读的错误信息
  def render_record_invalid(exception)
    render json: { error: exception.record.errors.full_messages.first || "参数校验失败" },
           status: :unprocessable_entity
  end

  # 422：数据库唯一索引冲突（并发重复提交时的兜底）
  def render_record_not_unique(_exception)
    render json: { error: "数据已存在，请勿重复提交" }, status: :unprocessable_entity
  end

  # 400：缺少必要参数
  def render_parameter_missing(exception)
    render json: { error: "缺少必要参数：#{exception.param}" }, status: :bad_request
  end

  # 500：未知异常统一兜底，日志中保留完整堆栈便于排查，响应中不暴露内部细节
  def render_internal_server_error(exception)
    Rails.logger.error("[500] #{exception.class}: #{exception.message}")
    Rails.logger.error(exception.backtrace.join("\n")) if exception.backtrace.present?

    render json: { error: "服务器内部错误，请稍后重试" }, status: :internal_server_error
  end
end
