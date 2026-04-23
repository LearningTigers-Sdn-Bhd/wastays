# frozen_string_literal: true

module HotelPortal
  class OnboardingSessionsController < HotelPortal::BaseController
    before_action :set_hotel

    def index
      @sessions = @current_hotel.onboarding_sessions
        .order(scheduled_at: :desc, created_at: :desc)
    end

    def cancel
      @session = @current_hotel.onboarding_sessions.find(params[:id])
      result = HotelPortal::CancelOnboardingSession.new(@session, params[:cancel_reason]).call

      if result.success?
        redirect_to hotel_onboarding_sessions_path(@current_hotel), notice: "Onboarding session cancelled."
      else
        redirect_to hotel_onboarding_sessions_path(@current_hotel), alert: result.error
      end
    end

    private

    def set_hotel
      @current_hotel = current_hotel
      unless @current_hotel
        redirect_to admin_hotels_path, alert: "Select a hotel before viewing the portal."
      end
    end
  end
end
