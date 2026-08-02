# frozen_string_literal: true

module NightAudits
  class DetectMissedArrivals
    def self.call(night_audit:, user:)
      Processing::DetectMissedArrivals.call(night_audit: night_audit, user: user)
    end

    def initialize(night_audit:, user:)
      @implementation = Processing::DetectMissedArrivals.new(night_audit: night_audit, user: user)
    end

    delegate :call, to: :@implementation
  end
end
