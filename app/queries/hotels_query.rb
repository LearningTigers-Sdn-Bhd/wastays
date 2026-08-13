# frozen_string_literal: true

class HotelsQuery
  STATUS_FILTERS = {
    "setup" => %w[setup],
    "pending_review" => %w[pending_review],
    "active" => %w[live],
    "suspended" => %w[suspended]
  }.freeze

  def initialize(relation = Hotel.all)
    @relation = relation
  end

  def call(params)
    relation = @relation.order(created_at: :desc, id: :desc)
    relation = relation.where(status: STATUS_FILTERS.fetch(params[:status])) if STATUS_FILTERS.key?(params[:status])
    relation = relation.search(params[:q]) if params[:q].present?
    relation = relation.includes(:onboarding_sessions) if params[:status] == "pending_review"
    relation
  end
end
