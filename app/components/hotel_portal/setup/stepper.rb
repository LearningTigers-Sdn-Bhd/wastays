# frozen_string_literal: true

module HotelPortal
  module Setup
    # The steps within the active phase, rendered under the navbar.
    #
    # The row always renders, including for a single-step phase. It is what tells
    # the owner which page they are on, so letting it appear and disappear
    # between phases would shift the whole page vertically on every navigation.
    class Stepper < PanelsUI::BaseComponent
      def initialize(presenter:)
        @presenter = presenter
      end

      attr_reader :presenter

      def steps = @steps ||= presenter.active_phase_entries

      def current_step_name = step_name(presenter.current_entry)

      def step_name(entry) = entry.definition.key

      def step_label(entry, index)
        label = "#{index + 1}. #{presenter.section_title(entry)}"
        enabled?(entry) ? label : "#{label} · Locked"
      end

      def enabled?(entry) = entry.available || entry == presenter.current_entry

      # Built from the presenter's hotel rather than the view's `current_hotel`,
      # so the component stays independent of controller state.
      def step_path(entry)
        helpers.hotel_onboarding_section_path(presenter.hotel, section_key: entry.definition.route_name)
      end
    end
  end
end
