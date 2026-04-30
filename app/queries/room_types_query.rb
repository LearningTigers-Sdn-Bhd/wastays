# frozen_string_literal: true

class RoomTypesQuery
  def initialize(relation)
    @relation = relation
  end

  def call(_params = {})
    @relation.order(created_at: :desc)
  end
end
