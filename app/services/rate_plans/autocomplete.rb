# frozen_string_literal: true

module RatePlans
  class Autocomplete
    DEFAULT_LIMIT = 20

    def self.call(...) = new(...).call

    def initialize(hotel:, query: nil, limit: DEFAULT_LIMIT)
      @hotel = hotel
      @query = query.to_s.strip
      @limit = limit.to_i.clamp(1, 50)
    end

    def call
      plans = hotel.rate_plans.active.where(kind: "custom").includes(:room_types)
      if query.present?
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
        plans = plans.where("rate_plans.name ILIKE ?", pattern)
      end

      plans.order(:name, :id).limit(limit).map do |plan|
        room_count = plan.room_types.size
        {
          id: plan.id,
          label: plan.name,
          description: "Used by #{room_count} #{'room category'.pluralize(room_count)}"
        }
      end
    end

    private

    attr_reader :hotel, :query, :limit
  end
end
