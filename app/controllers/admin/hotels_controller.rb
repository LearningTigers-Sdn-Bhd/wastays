# frozen_string_literal: true

class Admin::HotelsController < Admin::BaseController
  TAB_LABELS = {
    "hotel_details" => "Hotel details",
    "room_inventory" => "Room inventory",
    "channel_manager" => "Channel manager",
    "account_information" => "Account information",
    "banking_details" => "Banking details",
    "salesperson" => "Salesperson"
  }.freeze
  TAB_ICONS = {
    "hotel_details" => "building-2",
    "room_inventory" => "bed-double",
    "channel_manager" => "radio",
    "account_information" => "users",
    "banking_details" => "credit-card",
    "salesperson" => "user-round"
  }.freeze

  before_action :set_hotel, only: [ :show, :update ]
  before_action :load_salespersons, only: [ :new, :create ]
  before_action :set_plans, only: [ :new, :create ]
  before_action :set_breadcrumbs, only: [ :show, :new, :create, :update ]

  def index
    page_size = Admin::Hotels::IndexPresenter.normalize_page_size(params[:per_page])
    pagination, hotels = pagy(:offset, HotelsQuery.new.call(params), limit: page_size)
    @presenter = Admin::Hotels::IndexPresenter.new(
      hotels: hotels,
      pagination: pagination,
      summary: HotelsSummaryQuery.new.call,
      status: params[:status],
      page_size: page_size
    )
  end

  def show
    @active_tab = TAB_LABELS.key?(params[:tab]) ? params[:tab] : "hotel_details"
    @configured_margin_rate = @hotel.effective_margin_rate
    case @active_tab
    when "hotel_details"
      set_plans
    when "room_inventory"
      @room_types = @hotel.room_types.includes(rooms: :room_group).order(:name)
    when "channel_manager"
      @room_type_count = @hotel.room_types.count
      @mapped_room_type_count = @hotel.room_types.joins(:channel_mapping).count
    when "account_information"
      @owners = @hotel.user_hotel_accesses.active.joins(:role)
        .where(roles: { slug: "hotel_owner" }).includes(:user).map(&:user).sort_by(&:name)
      @selected_owner = @owners.find { |owner| owner.id.to_s == params[:owner_id].to_s }
      @selected_owner ||= @owners.first if @owners.one?
      @account_users = @hotel.account.users.where.not(role: "salesperson").order(:created_at)
      @pending_owner_invitations = @hotel.staff_invitations.unaccepted.joins(:role)
        .where(roles: { slug: "hotel_owner" }).order(:created_at)
    when "banking_details"
      @banking_detail = @hotel.account.banking_detail
    when "salesperson"
      load_salespersons
    end
  end

  def new
    @form = Admin::Hotels::CreateForm.new
  end

  def create
    @form = Admin::Hotels::CreateForm.new(create_params)

    if @form.save(actor: current_user)
      message = if @form.verify_owner_account?
        "Hotel created and the owner account is ready to use."
      elsif @form.create_and_onboard?
        "Hotel created and the owner invitation was queued."
      else
        "Hotel created without sending the owner invitation."
      end
      stash_owner_credentials
      complete_create(destination: admin_hotel_path(@form.hotel), notice: message)
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    result = Admin::Hotels::UpdateService.new(
      hotel: @hotel,
      hotel_params: update_hotel_params
    ).call

    if result.success?
      destination = params[:tab] == "channel_manager" ? admin_hotel_path(@hotel, tab: "channel_manager") : admin_hotel_path(@hotel)
      notice = params[:tab] == "channel_manager" ? "Channel manager preference saved." : "Hotel details saved."
      redirect_to destination, notice:
    else
      @hotel.errors.add(:base, result.error)
      show
      render :show, status: :unprocessable_content
    end
  end

  private

  def set_hotel
    @hotel = Hotel.locate!(params[:id])
  end

  def load_salespersons
    @salespersons = current_user.account.users.where(role: "salesperson").order(:name)
  end

  def set_plans
    @plans = Plan.active.ordered
  end

  def set_breadcrumbs
    if @hotel&.persisted?
      append_breadcrumb @hotel.name, admin_hotel_path(@hotel)
    else
      append_breadcrumb "New"
    end
  end

  def create_params
    params.fetch(:admin_hotels_create_form, {}).permit(
      :account_name,
      :owner_name,
      :owner_email,
      :hotel_name,
      :sell_mode,
      :plan_id,
      :preferred_channel_manager,
      :salesperson_id,
      :creation_action,
      :verify_owner_account,
      :allow_boat_information,
      :hide_payout_reports
    )
  end

  # The generated password is never persisted in readable form, so the only
  # chance to hand it over is the redirect that follows creation. Flash rides
  # in the encrypted session cookie and clears itself after one render.
  def stash_owner_credentials
    return if @form.generated_password.blank?

    flash[:owner_credentials] = {
      "email" => @form.owner&.email,
      "password" => @form.generated_password
    }
  end

  def complete_create(destination:, notice:)
    respond_to do |format|
      format.turbo_stream do
        flash[:notice] = notice
        render body: helpers.turbo_stream_action_tag(
          :complete_sheet,
          target: "admin_hotel_action_sheet",
          url: destination
        ), content_type: Mime[:turbo_stream]
      end
      format.html { redirect_to destination, notice: notice, status: :see_other }
    end
  end

  def update_hotel_params
    params.require(:hotel).permit(:name, :address, :city, :country, :star_rating, :hotel_prefix, :preferred_channel_manager, :plan_id, :sell_mode, :allow_boat_information, :hide_payout_reports,
      :grc_tablet_signing_enabled, amenities: [])
  end
end
