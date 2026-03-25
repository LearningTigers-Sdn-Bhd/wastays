class Hotel::PropertyPoliciesController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_hotel_access!

  def edit
    @hotel = current_hotel
    @property_policy = @hotel.property_policy || @hotel.build_property_policy
    authorize @hotel, policy_class: HotelPolicy
  end

  def update
    @hotel = current_hotel
    @property_policy = @hotel.property_policy || @hotel.build_property_policy
    authorize @hotel, policy_class: HotelPolicy

    if @property_policy.update(property_policy_params)
      # Move status to rooms_incomplete if it was profile_incomplete
      @hotel.update(status: 'rooms_incomplete') if @hotel.status == 'profile_incomplete'
      
      redirect_to hotel_dashboard_path, notice: "Hotel policies updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def property_policy_params
    params.require(:property_policy).permit(:check_in_time, :check_out_time, :cancellation_policy)
  end
end
