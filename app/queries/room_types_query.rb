# frozen_string_literal: true

class RoomTypesQuery
  def initialize(relation)
    @relation = relation
  end

  def call(params = {})
    relation = @relation.order(created_at: :desc)

    relation = search(relation, params[:q])

    relation
  end

  private

  def search(relation, query)
    return relation if query.blank?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.strip)}%"
    relation
      .left_joins(room_type_rate_plans: :rate_plan)
      .where("room_types.name ILIKE :term OR rate_plans.name ILIKE :term", term: term)
      .distinct
  end
end
