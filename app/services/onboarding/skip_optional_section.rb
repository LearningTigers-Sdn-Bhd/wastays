# frozen_string_literal: true

module Onboarding
  # An owner deciding a section does not apply to their property.
  #
  # Onboarding::Readiness blocks submission for an optional section that is
  # neither complete nor skipped, so "I sell no extras" has to be recorded as an
  # answer rather than left as silence. This covers the sections whose skip is
  # purely a decision; a section that also has to discard onboarding-only records
  # keeps its own service (see DecideNoAdditionalStaff).
  #
  # Nothing is deleted. A property that configured charges and then skipped is
  # contradicting itself, so the counts go into the audit metadata where review
  # can see them, rather than being silently resolved by destroying real records.
  class SkipOptionalSection
    Result = ApplicationResult.define(:section)

    DECISIONS = {
      "extra_charges" => { source: "extra_charge_setup", decision: "no_extra_charges" },
      "discounts" => { source: "discount_setup", decision: "no_discounts" },
      # Skipping leaves any logins the owner already typed in place. Unlike a
      # corporate draft, an OTA credential has no delivery waiting on it, so
      # there is nothing to defuse by discarding it — only the owner's typing to
      # lose. The admin's preferred provider is untouched either way.
      "channel_manager" => { source: "channel_manager_setup", decision: "no_channel_manager_now" }
    }.freeze

    def self.call(...) = new(...).call

    def initialize(hotel:, actor:, section_key:)
      @hotel = hotel
      @actor = actor
      @section_key = section_key.to_s
    end

    def call
      decision = DECISIONS.fetch(@section_key) do
        return Result.failure("This onboarding section cannot be skipped.", section: nil)
      end

      result = UpdateSection.new(
        hotel: @hotel,
        section_key: @section_key,
        state: "skipped",
        actor: @actor,
        metadata: decision.merge(record_count: record_count)
      ).call
      return Result.failure(result.error, section: result.section) unless result.success?

      Result.success(section: result.section)
    end

    private

    def record_count
      case @section_key
      when "extra_charges" then @hotel.hotel_extra_charges.count
      when "discounts" then @hotel.hotel_discounts.count
      when "channel_manager" then @hotel.hotel_ota_credentials.count
      end
    end
  end
end
