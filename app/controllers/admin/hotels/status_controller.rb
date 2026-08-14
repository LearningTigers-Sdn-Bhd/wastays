class Admin::Hotels::StatusController < Admin::BaseController
  before_action :set_hotel

  def approve
    if @hotel.status == "pending_review"
      redirect_to onboarding_admin_hotel_path(@hotel), alert: "Review the submitted setup before approving this property."
      return
    end

    result = Admin::Hotels::ApproveService.new(hotel: @hotel).call

    if result.success?
      notice = result.reactivating? ? "Account and hotel have been reactivated." : "Hotel has been approved."
      redirect_to admin_hotel_path(@hotel), notice: notice
    else
      redirect_to admin_hotel_path(@hotel), alert: "Failed to approve hotel: #{result.error}"
    end
  end

  def suspend
    result = Admin::Hotels::SuspendService.new(hotel: @hotel).call

    if result.success?
      redirect_to admin_hotel_path(@hotel), notice: "Account and hotel have been suspended."
    else
      redirect_to admin_hotel_path(@hotel), alert: "Failed to suspend account and hotel: #{result.error}"
    end
  end

  private

  def set_hotel
    @hotel = Hotel.locate!(params[:id])
  end
end
