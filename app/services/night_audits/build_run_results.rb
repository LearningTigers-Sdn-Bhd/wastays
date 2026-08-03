# frozen_string_literal: true

module NightAudits
  class BuildRunResults
    def self.call(night_audit:)
      Reporting::BuildRunResults.call(night_audit: night_audit)
    end

    def initialize(night_audit:)
      @implementation = Reporting::BuildRunResults.new(night_audit: night_audit)
    end

    delegate :call, to: :@implementation
  end
end
