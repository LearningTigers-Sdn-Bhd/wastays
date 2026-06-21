# frozen_string_literal: true

class HotelPortal::HotelTaxesController < HotelPortal::BaseController
  before_action :authorize!
  before_action :set_tax, only: %i[edit update destroy]

  def index
    redirect_to hotel_taxes_fees_path(current_hotel, tab: "tax_listing")
  end

  def new
    @hotel_tax = current_hotel.hotel_taxes.build(enabled: true, rate_type: "flat", charge_type: "tax")
    render "hotel_portal/taxes_fees/new"
  end

  def edit
    render "hotel_portal/taxes_fees/edit"
  end

  def create
    @hotel_tax = current_hotel.hotel_taxes.build(tax_params)
    if @hotel_tax.save
      redirect_to hotel_taxes_fees_path(current_hotel, tab: "tax_listing"), notice: "Tax added."
    else
      render "hotel_portal/taxes_fees/new", status: :unprocessable_entity
    end
  end

  def update
    if @hotel_tax.update(tax_params)
      redirect_to hotel_taxes_fees_path(current_hotel, tab: "tax_listing"), notice: "Tax updated."
    else
      render "hotel_portal/taxes_fees/edit", status: :unprocessable_entity
    end
  end

  def destroy
    @hotel_tax.destroy
    redirect_to hotel_taxes_fees_path(current_hotel, tab: "tax_listing"), notice: "Tax removed."
  end

  private

  def set_tax
    @hotel_tax = current_hotel.hotel_taxes.find(params[:id])
  end

  def tax_params
    params.require(:hotel_tax).permit(:name, :code, :charge_type, :rate_type, :amount, :enabled, :foreign_guests_only)
  end

  def authorize!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
  end

  def render_taxes_fees(status:)
    @hotel = current_hotel
    @presenter = HotelPortal::TaxesFeesPresenter.new(
      hotel: @hotel,
      current_user: current_user,
      hotel_tax: @hotel_tax
    )
    render "hotel_portal/taxes_fees/show", status: status
  end
end
