# frozen_string_literal: true

class HotelsQuery
  def initialize(relation = Hotel.all)
    @relation = relation
  end

  def call(params)
    relation = @relation.order(created_at: :desc)
    relation = relation.where(status: params[:status]) if params[:status].present? && params[:status] != "All Status"
    relation = relation.search(params[:q]) if params[:q].present?
    relation
  end
end
