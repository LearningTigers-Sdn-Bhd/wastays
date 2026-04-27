class Admin::Hotels::ChannelManagersController < Admin::BaseController
  before_action :set_hotel

  def onboard_channex
    result = Admin::Hotels::OnboardChannexService.new(hotel: @hotel).call

    if result.success?
      redirect_to admin_hotel_path(@hotel), notice: "Hotel successfully onboarded to Channex."
    else
      redirect_to admin_hotel_path(@hotel), alert: "Onboarding failed: #{result.message}"
    end
  end

  def disconnect_channex
    result = ChannelManagers::DisconnectService.new(hotel: @hotel).call

    if result.success?
      redirect_to admin_hotel_path(@hotel), notice: "Disconnected from Channex. Channel mappings removed."
    else
      redirect_to admin_hotel_path(@hotel), alert: "Failed to disconnect: #{result.error}"
    end
  end

  private

  def set_hotel
    @hotel = Hotel.find(params[:id])
  end
end
