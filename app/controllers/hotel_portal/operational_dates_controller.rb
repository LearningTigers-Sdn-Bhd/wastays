# frozen_string_literal: true

module HotelPortal
  class OperationalDatesController < BaseController
    skip_before_action :load_staff_notifications

    def show
      response.headers["Cache-Control"] = "no-store"
      render json: OperationalDatesPresenter.new(hotel: current_hotel)
    end
  end
end
