# frozen_string_literal: true

module GuestUI
  # A status as a pill: an icon, a word, and a tint.
  #
  # The word and the icon are the status. The tint only repeats them, so a
  # guest who cannot tell the tones apart still reads the whole thing.
  class StatusBadge < GuestUI::BaseComponent
    TONES = %i[success info warning destructive muted].freeze

    def initialize(label:, tone: :muted, icon: nil, class: nil, **attributes)
      @label = label
      @tone = TONES.include?(tone) ? tone : :muted
      @icon = icon
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      tag.span(**@attributes, class: tw_merge("guest-status-badge", @class), data: { tone: @tone }) do
        safe_join([
          (helpers.app_icon(@icon, class: "size-3.5 shrink-0", aria: { hidden: "true" }) if @icon),
          @label
        ].compact)
      end
    end
  end
end
