# frozen_string_literal: true

class Admin::HotelsController < Admin::BaseController
  before_action :set_hotel, only: [ :show, :edit, :update ]
  before_action :load_salespersons, only: [ :new, :create, :edit, :update ]
  before_action :set_breadcrumbs, only: [ :show, :new, :edit, :create, :update ]

  def index
    @all_hotels = HotelsQuery.new.call(params)
    @hotels = @all_hotels.page(params[:page]).per(25)

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def show
    @configured_margin_rate = @hotel.effective_margin_rate
  end

  def new
    @form = Admin::Hotels::CreateForm.new
    @hotel = @form.hotel
  end

  def create
    @form = Admin::Hotels::CreateForm.new(create_params)

    if @form.save
      redirect_to admin_hotel_path(@form.hotel), notice: "Hotel created successfully. Default password: #{HotelOps::CreateHotel::DEFAULT_PASSWORD}."
    else
      @hotel = @form.hotel
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

  def set_breadcrumbs
    if @hotel&.persisted?
      append_breadcrumb @hotel.name, admin_hotel_path(@hotel)
      append_breadcrumb "Edit" if action_name.in?([ "edit", "update" ])
    else
      append_breadcrumb "New"
    end
  end

  def create_params
    {
      account_name: params.dig(:account, :name),
      user_name: params.dig(:user, :name),
      user_email: params.dig(:user, :email),
      hotel_name: params.dig(:hotel, :name),
      address: params.dig(:hotel, :address),
      city: params.dig(:hotel, :city),
      country: params.dig(:hotel, :country),
      star_rating: params.dig(:hotel, :star_rating),
      salesperson_id: params.dig(:hotel, :salesperson_id),
      preferred_channel_manager: params.dig(:hotel, :preferred_channel_manager),
      amenities: params.dig(:hotel, :amenities)
    }
  end

  def update_hotel_params
    params.require(:hotel).permit(:name, :address, :city, :country, :star_rating, :hotel_prefix, :salesperson_id, :preferred_channel_manager, :plan_id, :pax_pricing_only, amenities: [])
  end

  def salesperson_name_param
    params.dig(:hotel, :salesperson_name).to_s.strip
  end

  def salesperson_email_param
    params.dig(:hotel, :salesperson_email).to_s.strip
  end
end
