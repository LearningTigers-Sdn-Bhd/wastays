# frozen_string_literal: true

module GuestUI
  # The bar at the top of every guest portal page.
  #
  # On a phone it names the page and gives the way back, because the
  # BottomNav already holds the destinations. From md up there is no bottom
  # bar, so the destinations move up here beside the logo.
  #
  # The `actions` slot takes the account menu. It shows at every size: a
  # guest on a phone has to be able to sign out too.
  class Navbar < GuestUI::BaseComponent
    renders_one :actions

    def initialize(home_path:, items: [], title: nil, back_path: nil, back_label: "Back",
                   class: nil, **attributes)
      @home_path = home_path
      @items = items
      @title = title
      @back_path = back_path
      @back_label = back_label
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    private

    attr_reader :home_path, :items, :title, :back_path, :back_label

    # With a title, a phone shows the title and the logo waits for md. With
    # none -- signed out -- the logo is all there is to show.
    def brand_class = title.present? ? "guest-navbar__brand max-md:hidden" : "guest-navbar__brand"

    def navbar_attributes
      @attributes.merge(class: tw_merge("guest-navbar", @class))
    end
  end
end
