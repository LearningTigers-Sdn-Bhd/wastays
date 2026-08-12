# frozen_string_literal: true

module Onboarding
  # Moves completed downstream setup back to needs-attention without touching
  # the domain records it summarizes. Upstream services decide whether a change
  # is material; this class owns the consistent transition and audit metadata.
  class InvalidateDependentSections
    Result = ApplicationResult.define(:section_keys)

    def self.call(...) = new(...).call

    def initialize(hotel:, section_keys:, actor:, source:, explanation:)
      @hotel = hotel
      @section_keys = Array(section_keys).map(&:to_s)
      @actor = actor
      @source = source
      @explanation = explanation
    end

    def call
      invalidated = []
      @section_keys.each do |section_key|
        section = @hotel.onboarding_sections.find_by(section_key: section_key)
        next unless section&.state == "complete"

        result = UpdateSection.new(
          hotel: @hotel,
          section_key: section_key,
          state: "needs_attention",
          actor: @actor,
          metadata: {
            source: @source,
            explanation: @explanation,
            invalidated_by: "rooms"
          }
        ).call
        return Result.failure(result.error, section_keys: invalidated) unless result.success?

        invalidated << section_key
      end

      Result.success(section_keys: invalidated)
    end
  end
end
