# frozen_string_literal: true

module HotelPortal
  class TransactionCodesPresenter
    TABS = [
      { name: "default_codes", label: "Default Codes", icon: "badge-percent" },
      { name: "additional_service_codes", label: "Additional Service Codes", icon: "plus" }
    ].freeze

    attr_reader :hotel, :active_tab, :current_user

    def initialize(hotel:, active_tab:, current_user:)
      @hotel = hotel
      @active_tab = active_tab
      @current_user = current_user
    end

    def tabs
      TABS
    end
  end
end
