class Admin::HotelsController < Admin::BaseController
  include Admin::HotelParamsHandler

  before_action :set_hotel, only: [ :show, :edit, :update ]
  before_action :load_salespersons, only: [ :new, :create, :edit, :update ]

  def index
    @hotels = Hotel.all.order(created_at: :desc)
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
end
