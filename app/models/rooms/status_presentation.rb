# frozen_string_literal: true

module Rooms
  # One mapping from a room's operational status to a PanelsUI::Badge variant,
  # shared by Stay View and the housekeeping board so the same status cannot
  # end up looking like two different things on two pages.
  module StatusPresentation
    BADGE_VARIANTS = {
      ready: :success,
      dirty: :warning,
      cleaning: :info,
      awaiting_inspection: :info,
      inspection_failed: :destructive,
      out_of_service: :destructive,
      # Occupied and late checkout are states of the stay rather than faults,
      # so neither takes the destructive tone.
      occupied: :accent,
      late_checkout_detected: :warning
    }.freeze

    def self.badge_variant(status)
      BADGE_VARIANTS.fetch(status.to_s.to_sym, :neutral)
    end
  end
end
