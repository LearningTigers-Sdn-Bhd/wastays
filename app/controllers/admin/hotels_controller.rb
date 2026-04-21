class Admin::HotelsController < Admin::BaseController
  before_action :set_hotel, only: [ :show, :edit, :update, :approve, :suspend, :onboard_channex, :disconnect_channex ]

  def index
    @hotels = Hotel.all.order(created_at: :desc)
  end

  def show
    month_to_date_bookings = @hotel.bookings.revenue_generating.where(created_at: Time.current.all_month)

    @gross_revenue_mtd = month_to_date_bookings.sum(:total_amount)
    @wastays_margin_mtd = month_to_date_bookings.sum("COALESCE(margin_amount, 0)")
    @hotel_net_earnings_mtd = month_to_date_bookings.sum("COALESCE(net_amount, 0)")
    @booking_count_mtd = month_to_date_bookings.count
    @configured_margin_rate = @hotel.effective_margin_rate
  end

  def new
    @hotel = Hotel.new
  end

  def create
    @hotel = Hotel.new(create_hotel_params)
    result = HotelOps::CreateHotel.new(
      account_params: account_params,
      user_params: user_params,
      hotel_params: create_hotel_params
    ).call

    if result[:success]
      redirect_to admin_hotel_path(result[:hotel]), notice: "Hotel created successfully. Default password: #{HotelOps::CreateHotel::DEFAULT_PASSWORD}."
    else
      @hotel.errors.add(:base, result[:error])
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @hotel.update(update_hotel_params)
      redirect_to admin_hotel_path(@hotel), notice: "Hotel updated successfully."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def approve
    reactivating = @hotel.status == "suspended" || @hotel.account.status == "suspended"

    ActiveRecord::Base.transaction do
      @hotel.account.update!(status: "active")
      @hotel.update!(status: "approved")
    end

    notice = reactivating ? "Account and hotel have been reactivated." : "Hotel has been approved."
    redirect_to admin_hotel_path(@hotel), notice: notice
  rescue ActiveRecord::RecordInvalid
    redirect_to admin_hotel_path(@hotel), alert: "Failed to approve hotel."
  end

  def suspend
    ActiveRecord::Base.transaction do
      @hotel.account.update!(status: "suspended")
      @hotel.update!(status: "suspended")
    end

    redirect_to admin_hotel_path(@hotel), notice: "Account and hotel have been suspended."
  rescue ActiveRecord::RecordInvalid
    redirect_to admin_hotel_path(@hotel), alert: "Failed to suspend account and hotel."
  end

  def onboard_channex
    @hotel.update!(preferred_channel_manager: "channex")
    result = ChannelManagers::OnboardingService.new(hotel: @hotel).call

    if result.success?
      redirect_to admin_hotel_path(@hotel), notice: "Hotel successfully onboarded to Channex."
    else
      redirect_to admin_hotel_path(@hotel), alert: "Onboarding failed: #{result.message}"
    end
  end

  def disconnect_channex
    @hotel.update!(preferred_channel_manager: nil)
    @hotel.channel_mapping&.destroy
    @hotel.room_types.each { |rt| rt.channel_mapping&.destroy }
    # Note: We don't delete rate plans as they are now part of our core model

    redirect_to admin_hotel_path(@hotel), notice: "Disconnected from Channex. Channel mappings removed."
  end

  private

  def set_hotel
    @hotel = Hotel.find(params[:id])
  end

  def create_hotel_params
    params.require(:hotel).permit(:name, :address, :city, :country, :star_rating, :preferred_channel_manager).merge(status: "approved")
  end

  def update_hotel_params
    params.require(:hotel).permit(:name, :address, :city, :country, :star_rating, :preferred_channel_manager)
  end

  def account_params
    params.require(:account).permit(:name)
  end

  def user_params
    params.require(:user).permit(:name, :email)
  end
end
