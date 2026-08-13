# frozen_string_literal: true

module Onboarding
  # Sends a completed Room revenue section back to `needs_attention` when the
  # taxes it was completed against no longer look the same.
  #
  # Scoped by fingerprint on purpose: an owner iterating on a fee that room
  # revenue does not assign should not keep re-opening a step they finished.
  # Nothing is deleted — the tax rules stay exactly as configured and the owner
  # is asked to confirm them again.
  class InvalidateRoomRevenue
    def self.call(...) = new(...).call

    def initialize(hotel:, actor: nil)
      @hotel = hotel
      @actor = actor
    end

    def call
      return false if section.blank? || section.state != "complete"

      stored = section.decision_metadata["tax_fingerprint"]
      return false if stored.blank?

      current = TaxFingerprint.call(@hotel)
      return false if stored == current

      UpdateSection.new(
        hotel: @hotel,
        section_key: "room_revenue",
        state: "needs_attention",
        actor: @actor,
        metadata: {
          source: "tax_change",
          explanation: "The taxes assigned to room revenue changed. Review the tax rules and confirm them again.",
          tax_fingerprint: current
        }
      ).call.success?
    end

    private

    def section
      @section ||= @hotel.onboarding_sections.find_by(section_key: "room_revenue")
    end
  end
end
