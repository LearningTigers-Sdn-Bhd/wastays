# frozen_string_literal: true

module GuestUI
  # One hotel service with the whole card as its link.
  class ActionCard < GuestUI::BaseComponent
    TONES = %i[booking issue discovery contact conversation].freeze

    def initialize(label:, href:, icon:, hint: nil, tone:, class: nil, **attributes)
      @label = label
      @href = href
      @icon = icon
      @hint = hint
      @tone = TONES.include?(tone) ? tone : :contact
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      tag.a(**card_attributes) do
        safe_join([
          helpers.app_icon(@icon, class: "guest-action-card__icon guest-service-surface__icon", aria: { hidden: "true" }),
          tag.span(class: "guest-action-card__text") do
            safe_join([
              tag.span(@label, class: "guest-action-card__label"),
              (tag.span(@hint, class: "guest-action-card__hint") if @hint.present?)
            ].compact, " ")
          end
        ])
      end
    end

    private

    def card_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        href: helpers.url_for(@href),
        class: tw_merge("guest-action-card guest-service-surface focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background", @class),
        data: data.merge(tone: @tone)
      )
    end
  end
end
