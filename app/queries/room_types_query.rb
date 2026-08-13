# frozen_string_literal: true

class RoomTypesQuery
  def initialize(relation)
    @relation = relation
  end

  def call(params = {})
    relation = @relation.order(created_at: :desc)

    relation = filter_room_groups(relation, params[:room_group_ids])
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

  def filter_room_groups(relation, values)
    values = Array(values).compact_blank.map(&:to_s).uniq
    return relation if values.empty?

    include_unassigned = values.delete("unassigned")
    requested_ids = values.filter_map { |value| Integer(value, exception: false) }
    valid_ids = relation.reorder(nil).where(room_group_id: requested_ids).distinct.pluck(:room_group_id)
    return relation if valid_ids.empty? && !include_unassigned

    predicates = []
    predicates << relation.klass.arel_table[:room_group_id].in(valid_ids) if valid_ids.any?
    predicates << relation.klass.arel_table[:room_group_id].eq(nil) if include_unassigned
    relation.where(predicates.reduce(:or))
  end
end
