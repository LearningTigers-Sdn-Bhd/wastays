# frozen_string_literal: true

module GuestUI
  # One number with its name: how many bookings, stays to come, refunds asked.
  #
  # The icon sits in a tinted chip over the number, and the label follows in
  # small type. Stacked, not side by side, so the cards stay narrow. The tone
  # only tells the cards apart; the label is the name.
  class StatCard < GuestUI::BaseComponent
    TONES = %i[info success warning destructive muted].freeze

    def initialize(label:, value:, icon:, tone: :muted, class: nil)
      @label = label
      @value = value
      @icon = icon
      @tone = TONES.include?(tone) ? tone : :muted
      @class = binding.local_variable_get(:class)
    end

    def call
      tag.div(class: tw_merge("guest-stat-card", @class), data: { tone: @tone }) do
        safe_join([
          tag.span(helpers.app_icon(@icon, class: "size-4", aria: { hidden: "true" }), class: "guest-stat-card__icon"),
          tag.p(@value, class: "guest-stat-card__value"),
          tag.p(@label, class: "guest-stat-card__label")
        ])
      end
    end
  end
end
