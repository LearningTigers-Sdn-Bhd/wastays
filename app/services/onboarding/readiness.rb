# frozen_string_literal: true

module Onboarding
  class Readiness
    Finding = Data.define(:section_key, :severity, :message)
    Result = Data.define(:ready, :blocking_issues, :warnings)

    def initialize(hotel:)
      @hotel = hotel
    end

    def call
      InitializeProgress.new(hotel: @hotel).call if @hotel.onboarding_sections.size < SectionCatalog.keys.size
      states = @hotel.onboarding_sections.index_by(&:section_key)
      blocking = []
      warnings = []

      SectionCatalog.all.each do |section|
        record = states.fetch(section.key)
        if record.state == "needs_attention"
          blocking << Finding.new(section_key: section.key, severity: :blocking, message: "This section needs attention.")
        elsif section.required && record.state != "complete"
          blocking << Finding.new(section_key: section.key, severity: :blocking, message: "Complete this required section.")
        elsif !section.required && !record.resolved?
          blocking << Finding.new(section_key: section.key, severity: :blocking, message: "Configure this section or explicitly skip it.")
        elsif record.state == "skipped"
          warnings << Finding.new(section_key: section.key, severity: :warning, message: "This optional section was skipped.")
        end
      end

      Result.new(ready: blocking.empty?, blocking_issues: blocking.freeze, warnings: warnings.freeze)
    end
  end
end
