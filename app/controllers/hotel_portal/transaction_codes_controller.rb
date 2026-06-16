# frozen_string_literal: true

module HotelPortal
  class TransactionCodesController < HotelPortal::BaseController
    TABS = %w[default_codes additional_service_codes].freeze

    before_action :set_hotel
    before_action :authorize!

    def show
      @presenter = transaction_codes_presenter
      append_transaction_codes_tab_breadcrumb
    end

    private

    def set_hotel
      @hotel = current_hotel
    end

    def authorize!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
    end

    def transaction_codes_presenter(tab: active_tab)
      HotelPortal::TransactionCodesPresenter.new(
        hotel: @hotel,
        active_tab: tab,
        current_user: current_user
      )
    end

    def active_tab
      requested_tab = params[:tab].to_s
      return requested_tab if TABS.include?(requested_tab)

      "default_codes"
    end

    def append_transaction_codes_tab_breadcrumb
      append_breadcrumb({ label: tab_label(@presenter.active_tab), tab_label: true })
    end

    def tab_label(tab)
      @presenter.tabs.find { |item| item[:name] == tab }&.fetch(:label) || "Default Codes"
    end
  end
end
