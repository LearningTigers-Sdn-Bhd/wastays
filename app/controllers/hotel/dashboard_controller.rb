class Hotel::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_hotel_access!

  def index
    @hotels = policy_scope(Hotel)
    @current_hotel = current_hotel

    if %w[registered email_verified profile_incomplete rooms_incomplete inventory_incomplete].include?(@current_hotel.status)
      render :onboarding
    end
  end
end
