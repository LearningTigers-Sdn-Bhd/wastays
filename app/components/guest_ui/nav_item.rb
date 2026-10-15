# frozen_string_literal: true

module GuestUI
  # One destination in the guest portal. The Navbar and the BottomNav draw the
  # same list, so a destination is declared once and both bars agree on it.
  NavItem = Data.define(:label, :path, :icon, :active) do
    def initialize(label:, path:, icon:, active: false)
      super
    end
  end
end
