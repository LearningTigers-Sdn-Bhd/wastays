# frozen_string_literal: true

module Rooms
  # One mapping from a room's operational status to a PanelsUI::Badge variant,
  # shared by Stay View and the housekeeping board so the same status cannot
  # end up looking like two different things on two pages.
  #
  # Every status Rooms::StatusResolver can return appears here exactly once, and
  # in the order they are offered to the user, so this doubles as the list a
  # status filter is built from. A spec holds it to that.
  module StatusPresentation
    BADGE_VARIANTS = {
      ready: :success,
      dirty: :warning,
      cleaning: :info,
      # Occupied and late checkout are states of the stay rather than faults,
      # so neither takes the destructive tone.
      occupied: :accent,
      awaiting_inspection: :info,
      inspection_failed: :destructive,
      out_of_service: :destructive,
      late_checkout_detected: :warning
    }.freeze

    RESOLVED_STATUSES = BADGE_VARIANTS.keys.map(&:to_s).freeze

    def self.badge_variant(status)
      BADGE_VARIANTS.fetch(status.to_s.to_sym, :neutral)
    end

    # Titleizing capitalises every word, which is wrong for the small ones.
    LABELS = { out_of_service: "Out of Service" }.freeze

    # How a resolved status is written wherever it is shown -- a badge on the
    # board, an option in its filter, a cell in an export.
    def self.label(status)
      LABELS.fetch(status.to_s.to_sym) { status.to_s.humanize.titleize }
    end
  end
end
