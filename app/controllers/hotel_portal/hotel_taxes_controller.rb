# frozen_string_literal: true

class HotelPortal::HotelTaxesController < HotelPortal::SettingsBaseController
  include SheetActionCompletion

  before_action :authorize!
  before_action :set_tax, only: %i[edit update destroy]

  def index
    redirect_to hotel_taxes_fees_path(current_hotel)
  end

  def new
    @hotel_tax = current_hotel.hotel_taxes.build(enabled: true, rate_type: "flat", charge_type: "tax")
    render "hotel_portal/taxes_fees/new", layout: false
  end

  def edit
    render "hotel_portal/taxes_fees/edit", layout: false
  end

  def create
    @hotel_tax = current_hotel.hotel_taxes.build(tax_params)
    if @hotel_tax.save
      complete_tax_sheet("Tax or fee added.")
    else
      render "hotel_portal/taxes_fees/new", formats: :html, layout: false, status: :unprocessable_content
    end
  end

  def update
    if @hotel_tax.update(tax_params)
      if params[:registry_status].present?
        redirect_to hotel_taxes_fees_path(current_hotel, tab: "registry"), notice: "Tax or fee updated."
      else
        complete_tax_sheet("Tax or fee updated.")
      end
    else
      render "hotel_portal/taxes_fees/edit", formats: :html, layout: false, status: :unprocessable_content
    end
  end

  def destroy
    @hotel_tax.destroy
    redirect_to hotel_taxes_fees_path(current_hotel), notice: "Tax removed."
  end

  private

  def set_tax
    @hotel_tax = current_hotel.hotel_taxes.find(params[:id])
  end

  def tax_params
    params.require(:hotel_tax).permit(:name, :code, :charge_type, :rate_type, :amount, :enabled, :foreign_guests_only, :registration_number)
  end

  def authorize!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
  end

  def complete_tax_sheet(notice)
    complete_sheet_action(
      destination: hotel_taxes_fees_path(current_hotel, tab: "registry"),
      notice: notice,
      frame: turbo_frame_request_id.presence || "settings_action_sheet"
    )
  end
end
