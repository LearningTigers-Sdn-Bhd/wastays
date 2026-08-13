# frozen_string_literal: true

module RatePlans
  # Gives a newly attached room a usable starting price without asking the
  # attachment sheet to render pricing fields. Per-room offers follow Standard
  # Rate live; per-person offers materialize only this room's occupancy ladder.
  class BootstrapAssignment
    def self.call!(...) = new(...).call!

    def initialize(rate_plan:, room_type:)
      @rate_plan = rate_plan
      @room_type = room_type
    end

    def call!
      assignment = rate_plan.room_type_rate_plans.create!(
        room_type: room_type,
        pricing_mode: room_type.hotel.sells_per_person? ? "fixed" : "multiplier",
        pricing_value: room_type.hotel.sells_per_person? ? nil : 0
      )

      copy_per_person_prices!(assignment) if room_type.hotel.sells_per_person?
      assignment
    end

    private

    attr_reader :rate_plan, :room_type

    def copy_per_person_prices!(assignment)
      standard_assignment = room_type.room_type_rate_plans
        .includes(:occupancy_prices)
        .find_by(rate_plan_id: room_type.standard_rate_plan&.id)
      standard_prices = standard_assignment&.occupancy_prices&.index_by(&:adults) || {}

      (1..room_type.max_adults).each do |adults|
        price = standard_prices[adults]&.price || room_type.base_price.to_d * adults
        assignment.occupancy_prices.create!(adults: adults, price: price)
      end
    end
  end
end
