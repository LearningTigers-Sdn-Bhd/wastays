# frozen_string_literal: true

module NightAudits
  class Prepare
    Result = Data.define(:night_audit, :evaluation, :ready)

    def self.call(hotel:, business_date:, trigger_mode: "manual")
      new(hotel: hotel, business_date: business_date, trigger_mode: trigger_mode).call
    end

    def initialize(hotel:, business_date:, trigger_mode:)
      @hotel = hotel
      @business_date = business_date.to_date
      @trigger_mode = trigger_mode
    end

    def call
      evaluation = NightAudits::Evaluate.new(
        hotel: @hotel,
        business_date: @business_date,
        phase: :pre_close
      ).call

      audit = @hotel.night_audits.find_by(business_date: @business_date)
      Result.new(night_audit: audit, evaluation: evaluation, ready: !blocked?(evaluation))
    end

    private

    def blocked?(evaluation)
      evaluation[:blocked_details].values.flatten.any?
    end
  end
end
