class Hotel::ProfilesController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_hotel_access!

  def edit
    @hotel = current_hotel
    authorize @hotel
  end

  def update
    @hotel = current_hotel
    authorize @hotel

    if @hotel.update(hotel_params)
      # Move status from registered to profile_incomplete or email_verified etc based on roadmap
      # Section 7 says: registered -> email_verified -> profile_incomplete -> ...
      # For now, let's just move it to profile_incomplete if it was registered
      @hotel.update(status: 'profile_incomplete') if @hotel.status == 'registered'
      
      redirect_to hotel_dashboard_path, notice: "Hotel profile updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def hotel_params
    params.require(:hotel).permit(:name, :address, :city, :country, :star_rating)
  end
end
