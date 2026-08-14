class Admin::Hotels::ChannelManagersController < Admin::BaseController
  before_action :set_hotel

  def onboard_channex
    unless @hotel.feature_enabled?("manage_40_otas")
      redirect_to admin_hotel_path(@hotel), alert: "This hotel's plan does not include Channel Manager. Upgrade to Plus or Enterprise first."
      return
    end

    result = Admin::Hotels::OnboardChannexService.new(hotel: @hotel).call

    if result.success?
      redirect_to admin_hotel_path(@hotel), notice: "Hotel successfully onboarded to Channel Manager."
    else
      redirect_to admin_hotel_path(@hotel), alert: "Onboarding failed: #{result.message}"
    end
  end

  def full_refresh
    result = ChannelManagers::FullRefreshService.new(hotel: @hotel).call

    if result.success?
      redirect_to admin_hotel_path(@hotel), notice: result.message
    else
      redirect_to admin_hotel_path(@hotel), alert: "Full refresh failed: #{result.message}"
    end
  end

  def disconnect_channex
    result = ChannelManagers::DisconnectService.new(hotel: @hotel).call

    if result.success?
      redirect_to admin_hotel_path(@hotel), notice: "Disconnected from Channel Manager. Channel mappings removed."
    else
      redirect_to admin_hotel_path(@hotel), alert: "Failed to disconnect: #{result.error}"
    end
  end

  def repair_mapping
    result = ChannelManagers::RepairMappingService.new(hotel: @hotel).call

    if result.success?
      redirect_to admin_hotel_path(@hotel), notice: result.message
    else
      redirect_to admin_hotel_path(@hotel), alert: "Repair failed: #{result.message}"
    end
  end

  private

  def set_hotel
    @hotel = Hotel.locate!(params[:id])
  end
end
