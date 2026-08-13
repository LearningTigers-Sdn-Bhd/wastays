# frozen_string_literal: true

module HotelPortal
  module Setup
    # The six setup phases, rendered as the navbar's second row.
    #
    # A chevron progress bar: segments point forward and fill as the owner
    # advances, so the row reads as one journey with a direction rather than six
    # separate destinations. State travels on the marker glyph (check, lock,
    # warning, number) so it never depends on colour, with the full state word
    # carried for assistive tech.
    class PhaseNav < PanelsUI::BaseComponent
      # Phosphor bold: at 14px next to a semibold label, an outline stroke reads
      # thin and washed out against the filled segments.
      ICON_LIBRARY = { library: "phosphor", variant: "bold" }.freeze

      STATE_ICONS = {
        "complete" => "check",
        "skipped" => "minus",
        "needs_attention" => "warning"
      }.freeze

      def initialize(presenter:)
        @presenter = presenter
      end

      attr_reader :presenter

      def phases = @phases ||= presenter.phases

      def state_label(phase) = helpers.onboarding_state_label(phase.state)

      def available?(phase) = phase.entries.first.available

      def path(phase)
        helpers.hotel_onboarding_section_path(
          presenter.hotel,
          section_key: phase.entries.first.definition.route_name
        )
      end

      def icon_for(phase)
        return "lock" unless available?(phase)

        STATE_ICONS[phase.state]
      end

      # The rendered SVG carries no identifying attribute of its own, so the
      # marker names the glyph it chose.
      def marker_kind(phase) = icon_for(phase) || "number"

      # Where the owner is outranks how a phase is going: the current segment
      # takes the solid fill even when it also carries another state.
      def segment_state(phase)
        return "current" if phase.current
        return "locked" unless available?(phase)
        return "attention" if phase.state == "needs_attention"
        return "complete" if phase.state.in?(%w[complete skipped])

        "available"
      end
    end
  end
end
