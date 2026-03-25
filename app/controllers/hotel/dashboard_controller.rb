class Hotel::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_hotel_access!

  def index
    @hotels = policy_scope(Hotel)
    @current_hotel = current_hotel

    return unless @current_hotel # Handle superadmin with no hotels

    if @current_hotel.onboarding?
      render :onboarding
    end
  end

  def submit_for_review
    @hotel = current_hotel
    authorize @hotel, :update?, policy_class: HotelPolicy

    if @hotel.submit_for_review!
      redirect_to hotel_dashboard_path, notice: "Your hotel has been submitted for review. We will contact you soon."
    else
      redirect_to hotel_dashboard_path, alert: "Please complete all onboarding steps before submitting."
    end
  end
end
