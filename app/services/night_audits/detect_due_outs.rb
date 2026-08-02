# frozen_string_literal: true

module NightAudits
  class DetectDueOuts
    Result = Processing::DetectDueOuts::Result

    def self.call(night_audit:, user:)
      Processing::DetectDueOuts.call(night_audit: night_audit, user: user)
    end

    def initialize(night_audit:, user:)
      @implementation = Processing::DetectDueOuts.new(night_audit: night_audit, user: user)
    end

    delegate :call, to: :@implementation
  end
end
