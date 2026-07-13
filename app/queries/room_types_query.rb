# frozen_string_literal: true

class RoomTypesQuery
  def initialize(relation)
    @relation = relation
  end

  def call(params = {})
    relation = @relation.order(created_at: :desc)

    if params[:room_group_id].present?
      relation = if params[:room_group_id] == "unassigned"
        relation.where(room_group_id: nil)
      else
        relation.where(room_group_id: params[:room_group_id])
      end
    end

    relation
  end
end
