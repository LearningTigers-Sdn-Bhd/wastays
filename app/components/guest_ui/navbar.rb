# frozen_string_literal: true

module GuestUI
  # The bar at the top of every guest portal page.
  #
  # On a phone it names the page and gives the way back, because the
  # BottomNav already holds the destinations. From md up there is no bottom
  # bar, so the destinations move up here.
  #
  # The `actions` slot takes the account menu. It shows at every size: a
  # guest on a phone has to be able to sign out too.
  class Navbar < GuestUI::BaseComponent
    renders_one :actions

    def initialize(items: [], title: nil, back_path: nil, back_label: "Back",
                   class: nil, **attributes)
      @items = items
      @title = title
      @back_path = back_path
      @back_label = back_label
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    private

    attr_reader :items, :title, :back_path, :back_label

    # From md up the links take the heading's place. With no links -- the
    # signed-out pages -- the heading stays at every size.
    def heading_class = items.any? ? "guest-navbar__heading md:hidden" : "guest-navbar__heading"

    def navbar_attributes
      @attributes.merge(class: tw_merge("guest-navbar", @class))
    end
  end
end
