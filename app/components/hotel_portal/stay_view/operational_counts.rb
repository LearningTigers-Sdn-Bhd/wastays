# frozen_string_literal: true

module HotelPortal
  module StayView
    class OperationalCounts < PanelsUI::BaseComponent
      PRESENTATION = {
        all: { label: "All", variant: :outline },
        vacant: { label: "Vacant", variant: :success },
        arrival: { label: "Arrival", variant: :info },
        occupied: { label: "Occupied", variant: :primary },
        departure: { label: "Departure", variant: :neutral },
        turnover: { label: "Turnover", variant: :warning },
        blocked: { label: "Blocked", variant: :destructive },
        dirty: { label: "Dirty", variant: :warning }
      }.freeze

      def initialize(counts:)
        @counts = counts
      end

      def before_render
        raise ArgumentError, "OperationalCounts requires StayView::StatusCounts" unless @counts.is_a?(::StayView::StatusCounts)
      end

      def call
        tag.div(
          safe_join(PRESENTATION.map { |state, presentation| badge(state, presentation) }),
          class: "flex flex-wrap gap-1.5",
          aria: { label: "Room summary for #{@counts.reference_date.to_fs(:long)}" },
          data: { slot: "stay-view-operational-counts" }
        )
      end

      private

      def badge(state, presentation)
        count = @counts.public_send(state)
        render PanelsUI::Badge.new(
          variant: presentation.fetch(:variant),
          size: :sm,
          shape: :rounded,
          class: "gap-1.5",
          aria: { label: "#{presentation.fetch(:label)}: #{helpers.pluralize(count, "room")}" },
          data: { slot: "stay-view-operational-count", state: }
        ) do
          safe_join([
            tag.span(presentation.fetch(:label)),
            tag.span(count, class: "font-semibold tabular-nums")
          ])
        end
      end
    end
  end
end
