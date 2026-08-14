# frozen_string_literal: true

class HotelsQuery
  STATUS_FILTERS = {
    "setup" => %w[setup],
    "pending_review" => %w[pending_review],
    "ready_to_launch" => %w[ready_to_launch],
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
    relation = relation.includes(:onboarding_sessions) if params[:status].in?(%w[pending_review ready_to_launch])
    relation
  end
end
