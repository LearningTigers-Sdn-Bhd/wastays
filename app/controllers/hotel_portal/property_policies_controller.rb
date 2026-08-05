class HotelPortal::PropertyPoliciesController < HotelPortal::BaseController
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
      @hotel.complete_policies!
      redirect_to hotel_dashboard_path, notice: "Hotel policies updated successfully."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def property_policy_params
    # Cancellation terms are no longer free prose here — they live on the structured
    # cancellation policy under Commercial → Room Revenue → Reservation policies.
    params.require(:property_policy).permit(:check_in_time, :check_out_time)
  end
end
