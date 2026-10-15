# frozen_string_literal: true

module GuestUI
  # One card of the Property Guide: a sage icon box, a title, and what the
  # property wrote under it. The Property Info page builds from it, and a
  # policy is one with rules in it.
  #
  # subtitle: the one fact a guest looks for first, such as "Check-in from
  # 15:00", set under the title so it reads before the body.
  #
  # action: one link out of the card, such as the map. It sits at the foot, so
  # the actions of the cards in a row line up.
  class GuideCard < GuestUI::BaseComponent
    def initialize(title:, icon: "info", subtitle: nil, action: nil, class: nil, **attributes)
      @title = title
      @icon = icon
      @subtitle = subtitle
      @action = action
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def render? = content.present? || @subtitle.present?

    private

    attr_reader :title, :icon, :subtitle, :action

    def card_attributes
      @attributes.merge(class: tw_merge("guest-guide-card", @class))
    end
  end
end
