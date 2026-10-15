# frozen_string_literal: true

module GuestUI
  # The guest portal's destinations on a phone, fixed to the bottom of the
  # screen where a thumb reaches them. From md up the Navbar holds the same
  # items, so this bar hides itself there.
  class BottomNav < GuestUI::BaseComponent
    def initialize(items:, class: nil, **attributes)
      @items = items
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def render? = @items.any?

    def call
      tag.nav(**nav_attributes) do
        safe_join(@items.map { |item| link(item) })
      end
    end

    private

    def link(item)
      link_to(item.path, class: "guest-bottom-nav__link", aria: { current: ("page" if item.active) }) do
        safe_join([
          helpers.app_icon(item.icon, class: "size-5", aria: { hidden: "true" }),
          tag.span(item.label)
        ])
      end
    end

    def nav_attributes
      @attributes.merge(
        class: tw_merge("guest-bottom-nav", @class),
        aria: { label: "Guest portal" }
      )
    end
  end
end
