# frozen_string_literal: true

module RatePlans
  # The single persistence boundary for one rate plan / room category price.
  # Both create and edit hand this service the same RoomPricing form object, so
  # generated occupancy ladders and their completeness rules cannot drift.
  class SaveRoomPricing
    Result = Data.define(:assignment, :pricing, :error) do
      def success? = error.nil?
    end

    def self.call(...) = new(...).call
    def self.call!(...) = new(...).call!

    def initialize(rate_plan:, room_type:, pricing:)
      @rate_plan = rate_plan
      @room_type = room_type
      @pricing = pricing
    end

    def call
      unless pricing.valid?
        return Result.new(assignment: nil, pricing: pricing, error: pricing.errors.full_messages.to_sentence)
      end

      assignment = call!
      Result.new(assignment: assignment, pricing: pricing, error: nil)
    rescue ActiveRecord::RecordInvalid => e
      pricing.errors.add(:base, e.record.errors.full_messages.to_sentence)
      Result.new(assignment: nil, pricing: pricing, error: pricing.errors.full_messages.to_sentence)
    end

    def call!
      raise ActiveRecord::RecordInvalid.new(rate_plan) unless pricing.valid?

      assignment = nil
      ActiveRecord::Base.transaction do
        assignment = rate_plan.room_type_rate_plans.find_or_initialize_by(room_type: room_type)
        assignment.update!(pricing.assignment_attributes)
        replace_occupancy_matrix!(assignment)
      end
      assignment
    end

    private

    attr_reader :rate_plan, :room_type, :pricing

    def replace_occupancy_matrix!(assignment)
      expected = pricing.occupancy_matrix
      assignment.occupancy_prices.where.not(adults: expected.keys).destroy_all

      expected.each do |adults, price|
        assignment.occupancy_prices.find_or_initialize_by(adults: adults).update!(price: price)
      end
    end
  end
end
