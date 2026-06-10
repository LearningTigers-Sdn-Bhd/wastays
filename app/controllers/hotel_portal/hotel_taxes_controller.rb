# frozen_string_literal: true

class HotelPortal::HotelTaxesController < HotelPortal::BaseController
  before_action :authorize!
  before_action :set_tax, only: %i[update destroy]

  def index
    redirect_to hotel_settings_path(current_hotel, tab: "tax")
  end

  def create
    @hotel_tax = current_hotel.hotel_taxes.build(tax_params)
    if @hotel_tax.save
      redirect_to hotel_settings_path(current_hotel, tab: "tax"), notice: "Tax added."
    else
      @hotel_taxes = current_hotel.hotel_taxes.order(:name)
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @hotel_tax.update(tax_params)
      redirect_to hotel_settings_path(current_hotel, tab: "tax"), notice: "Tax updated."
    else
      @hotel_taxes = current_hotel.hotel_taxes.order(:name)
      @hotel_tax_edit = @hotel_tax
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @hotel_tax.destroy
    redirect_to hotel_settings_path(current_hotel, tab: "tax"), notice: "Tax removed."
  end

  private

  def set_tax
    @hotel_tax = current_hotel.hotel_taxes.find(params[:id])
  end

  def tax_params
    params.require(:hotel_tax).permit(:name, :rate_type, :amount, :enabled, :foreign_guests_only)
  end

  def authorize!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
  end
end
