# frozen_string_literal: true

module GuestUI
  # One number with its name: how many bookings, how many stays to come.
  #
  # The label leads in small type and the number follows large, so a row of
  # them reads as a set of facts, not as a set of buttons.
  class StatCard < GuestUI::BaseComponent
    def initialize(label:, value:, icon: nil, class: nil)
      @label = label
      @value = value
      @icon = icon
      @class = binding.local_variable_get(:class)
    end

    def call
      tag.div(class: tw_merge("guest-stat-card", @class)) do
        safe_join([
          tag.p(class: "guest-stat-card__label") do
            safe_join([ (helpers.app_icon(@icon, class: "size-4 shrink-0", aria: { hidden: "true" }) if @icon), @label ].compact)
          end,
          tag.p(@value, class: "guest-stat-card__value")
        ])
      end
    end
  end
end
