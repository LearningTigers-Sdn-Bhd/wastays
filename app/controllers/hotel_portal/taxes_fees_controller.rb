# frozen_string_literal: true

module HotelPortal
  class TaxesFeesController < HotelPortal::BaseController
    before_action :set_hotel
    before_action :authorize!

    def show
      prepare_taxes_fees_page
    end

    def update
      form = HotelPortal::TaxSettingsForm.new(@hotel, params)

      if form.save
        redirect_to hotel_taxes_fees_path(@hotel), notice: "Tax settings updated successfully."
      else
        prepare_taxes_fees_page
        render :show, status: :unprocessable_entity
      end
    end

    private

    def set_hotel
      @hotel = current_hotel
    end

    def authorize!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
    end

    def prepare_taxes_fees_page
      @presenter = HotelPortal::TaxesFeesPresenter.new(
        hotel: @hotel,
        current_user: current_user,
        primary_edit: params[:primary_edit]
      )
    end
  end
end
