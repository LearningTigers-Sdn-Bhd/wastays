# frozen_string_literal: true

module GuestUI
  # The concierge page frame: the hotel's hero, one centred container, and the
  # footer.
  #
  # Two layouts. The split layout keeps the stay context at about a third and
  # the actions at about two thirds, so a guest acting on a stay never loses
  # track of which stay they are acting on. The centered layout is for a page
  # that has no context to keep -- a stay that has ended, a link that no longer
  # works.
  #
  # Both stack on a phone, and the DOM order already matches that reading
  # order, so the grid never moves focus away from the order the page is read
  # in.
  #
  # The hero is a slot rather than a fixed part of the frame. The chat fills
  # the viewport and names the hotel in its own bar, so it takes the frame
  # without one.
  class Page < GuestUI::BaseComponent
    VARIANTS = %i[split centered].freeze
    FOOTER_TEXT = "Powered by WAStays"

    renders_one :hero
    renders_one :context

    def initialize(variant: :split, footer: true, class: nil, **attributes)
      @variant = VARIANTS.include?(variant) ? variant : :split
      @footer = footer
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    private

    def footer? = @footer
    def columns = (@variant == :split && context?) ? 2 : 1

    def page_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        class: tw_merge("guest-page", @class),
        data: data.merge(variant: @variant)
      )
    end
  end
end
