# frozen_string_literal: true

module NightAudits
  class ProcessNoShowDetections
    def self.call(night_audit:, user:)
      Processing::ProcessNoShowDetections.call(night_audit: night_audit, user: user)
    end

    def initialize(night_audit:, user:)
      @implementation = Processing::ProcessNoShowDetections.new(night_audit: night_audit, user: user)
    end

    delegate :call, to: :@implementation
  end
end
