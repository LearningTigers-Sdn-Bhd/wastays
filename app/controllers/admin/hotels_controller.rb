# frozen_string_literal: true

class Admin::HotelsController < Admin::BaseController
  before_action :set_hotel, only: [ :show, :edit, :update ]
  before_action :load_salespersons, only: [ :new, :create, :edit, :update ]
  before_action :set_plans, only: [ :new, :create, :edit, :update ]
  before_action :set_breadcrumbs, only: [ :show, :new, :edit, :create, :update ]

  def index
    page_size = Admin::Hotels::IndexPresenter.normalize_page_size(params[:per_page])
    hotels = HotelsQuery.new.call(params).page(params[:page]).per(page_size)
    @presenter = Admin::Hotels::IndexPresenter.new(
      hotels: hotels,
      summary: HotelsSummaryQuery.new.call,
      status: params[:status],
      page_size: page_size
    )
  end

  def show
    @configured_margin_rate = @hotel.effective_margin_rate
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

  def edit; end

  def update
    result = Admin::Hotels::UpdateService.new(
      hotel: @hotel,
      hotel_params: update_hotel_params,
      salesperson_params: { name: salesperson_name_param, email: salesperson_email_param },
      current_user: current_user
    ).call

    if result.success?
      redirect_to admin_hotel_path(@hotel), notice: "Hotel updated successfully."
    else
      @hotel.errors.add(:base, result.error)
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_hotel
    @hotel = Hotel.friendly.find(params[:id])
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
      append_breadcrumb "Edit" if action_name.in?([ "edit", "update" ])
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
      :verify_owner_account
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
    params.require(:hotel).permit(:name, :address, :city, :country, :star_rating, :hotel_prefix, :salesperson_id, :preferred_channel_manager, :plan_id, :sell_mode, :allow_boat_information, amenities: [])
  end

  def salesperson_name_param
    params.dig(:hotel, :salesperson_name).to_s.strip
  end

  def salesperson_email_param
    params.dig(:hotel, :salesperson_email).to_s.strip
  end
end
