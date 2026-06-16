# frozen_string_literal: true

module HotelPortal
  class TaxesFeesController < HotelPortal::BaseController
    before_action :set_hotel
    before_action :authorize!

    def show
      @presenter = taxes_fees_presenter
      render "hotel_portal/taxes_fees/show"
    end

    def update
      form = HotelPortal::TaxSettingsForm.new(@hotel, params)

      if form.save
        redirect_to hotel_taxes_fees_path(@hotel, tab: "tax_listing"), notice: "Tax settings updated successfully."
      else
        @presenter = taxes_fees_presenter
        render "hotel_portal/taxes_fees/show", status: :unprocessable_entity
      end
    end

    private

    def set_hotel
      @hotel = current_hotel
    end

    def authorize!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
    end

    def taxes_fees_presenter
      HotelPortal::TaxesFeesPresenter.new(
        hotel: @hotel,
        current_user: current_user,
        primary_edit: params[:primary_edit]
      )
    end
  end
end
