# frozen_string_literal: true

class HotelPortal::GeneralLedgerMapsController < HotelPortal::SettingsBaseController
  before_action :authorize_manage_gl_maps!
  before_action :set_gl_map, only: %i[edit update]
  before_action :append_page_breadcrumb, only: :edit

  def index
    Financials::EnsureDefaultGlMaps.call(current_hotel)
    @gl_maps = current_hotel.hotel_general_ledger_maps.order(:transaction_category)
  end

  def edit
  end

  def update
    if @gl_map.update(gl_map_params)
      redirect_to hotel_general_ledger_maps_path(current_hotel), notice: "General Ledger mapping updated successfully."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def append_page_breadcrumb
    append_breadcrumb "Edit Mapping"
  end

  def authorize_manage_gl_maps!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_general_ledger_maps", hotel: current_hotel)
  end

  def set_gl_map
    @gl_map = current_hotel.hotel_general_ledger_maps.find(params[:id])
  end

  def gl_map_params
    params.require(:hotel_general_ledger_map).permit(:gl_code, :description)
  end
end
