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

    # Seven room statuses plus "occupied" cannot be told apart by hue alone --
    # three pairs above share a badge variant, and colour on its own is no use
    # to a colourblind user. Each status therefore carries a shape as well, and
    # the two travel together wherever a status is shown.
    ICONS = {
      ready: "circle-check",
      dirty: "spray-can",
      cleaning: "brush-cleaning",
      occupied: "bed",
      awaiting_inspection: "search-check",
      inspection_failed: "shield-x",
      out_of_service: "construction",
      late_checkout_detected: "clock"
    }.freeze

    UNKNOWN_ICON = "circle-question-mark"

    RESOLVED_STATUSES = BADGE_VARIANTS.keys.map(&:to_s).freeze

    def self.badge_variant(status)
      BADGE_VARIANTS.fetch(status.to_s.to_sym, :neutral)
    end

    def self.icon(status)
      ICONS.fetch(status.to_s.to_sym, UNKNOWN_ICON)
    end

    # Only a ready room can be assigned to an arriving guest; the board says so
    # rather than leaving staff to remember which of the seven counts as clean.
    def self.assignable?(status)
      RoomStatus::ASSIGNABLE_STATUSES.include?(status.to_s)
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
