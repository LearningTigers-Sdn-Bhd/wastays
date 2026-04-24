# frozen_string_literal: true

class Admin::HotelsController < Admin::BaseController
  before_action :set_hotel, only: [ :show, :edit, :update ]
  before_action :load_salespersons, only: [ :new, :create, :edit, :update ]

  def index
    @all_hotels = Hotel.all.order(created_at: :desc)
    
    # Apply filters
    @all_hotels = @all_hotels.where(status: params[:status]) if params[:status].present? && params[:status] != "All Status"
    @all_hotels = @all_hotels.search(params[:q]) if params[:q].present?

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
    @hotel = Hotel.new
  end

  def create
    @hotel = Hotel.new(create_hotel_params)
    result = HotelOps::CreateHotel.new(account_params: account_params, user_params: user_params, hotel_params: create_hotel_params).call

    if result[:success]
      redirect_to admin_hotel_path(result[:hotel]), notice: "Hotel created successfully. Default password: #{HotelOps::CreateHotel::DEFAULT_PASSWORD}."
    else
      @hotel.errors.add(:base, result[:error])
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
    @hotel = Hotel.find(params[:id])
  end

  def load_salespersons
    @salespersons = current_user.account.users.where(role: "salesperson").order(:name)
  end

  def create_hotel_params
    params.require(:hotel).permit(:name, :address, :city, :country, :star_rating, :salesperson_id, :preferred_channel_manager).merge(status: "approved")
  end

  def update_hotel_params
    params.require(:hotel).permit(:name, :address, :city, :country, :star_rating, :salesperson_id, :preferred_channel_manager)
  end

  def account_params
    params.require(:account).permit(:name)
  end

  def user_params
    params.require(:user).permit(:name, :email)
  end

  def salesperson_name_param
    params.dig(:hotel, :salesperson_name).to_s.strip
  end

  def salesperson_email_param
    params.dig(:hotel, :salesperson_email).to_s.strip
  end
end
