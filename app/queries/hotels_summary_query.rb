# frozen_string_literal: true

class HotelsSummaryQuery
  def initialize(relation = Hotel.all)
    @relation = relation
  end

  def call
    counts = @relation.reorder(nil).group(:status).count

    {
      total: counts.values.sum,
      setup: HotelsQuery::STATUS_FILTERS.fetch("setup").sum { |status| counts.fetch(status, 0) },
      pending_review: counts.fetch("pending_review", 0),
      ready_to_launch: counts.fetch("ready_to_launch", 0),
      active: HotelsQuery::STATUS_FILTERS.fetch("active").sum { |status| counts.fetch(status, 0) },
      suspended: counts.fetch("suspended", 0)
    }
  end
end
