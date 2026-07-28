# frozen_string_literal: true

module HotelPortal
  module StayView
    class OperationalCounts < PanelsUI::BaseComponent
      # Metric chips only — status colour lives on the board itself, so every
      # count reads in the same neutral outline style.
      LABELS = {
        all: "All",
        vacant: "Vacant",
        arrival: "Arrival",
        occupied: "Occupied",
        departure: "Departure",
        turnover: "Turnover",
        blocked: "Blocked",
        dirty: "Dirty"
      }.freeze
      # Turnover is a single-day room-card state; the timeline never renders it.
      HIDDEN_STATES = { timeline: %i[turnover].freeze }.freeze

      def initialize(counts:, view_mode: :rooms)
        @counts = counts
        @view_mode = view_mode.to_sym
      end

      def before_render
        raise ArgumentError, "OperationalCounts requires StayView::StatusCounts" unless @counts.is_a?(::StayView::StatusCounts)
      end

      def call
        tag.div(
          safe_join(visible_labels.map { |state, label| badge(state, label) }),
          class: "flex flex-wrap gap-1.5",
          aria: { label: "Room summary for #{@counts.reference_date.to_fs(:long)}" },
          data: { slot: "stay-view-operational-counts" }
        )
      end

      private

      def visible_labels
        LABELS.except(*HIDDEN_STATES.fetch(@view_mode, []))
      end

      def badge(state, label)
        count = @counts.public_send(state)
        render PanelsUI::Badge.new(
          variant: :outline,
          size: :sm,
          shape: :rounded,
          class: "gap-1.5",
          aria: { label: "#{label}: #{helpers.pluralize(count, "room")}" },
          data: { slot: "stay-view-operational-count", state: }
        ) do
          safe_join([
            tag.span(label),
            tag.span(count, class: "font-semibold tabular-nums")
          ])
        end
      end
    end
  end
end
