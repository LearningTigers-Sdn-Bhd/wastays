class Admin::HotelsController < Admin::BaseController
  before_action :set_hotel, only: [ :show, :edit, :update, :approve, :suspend, :onboard_channex, :disconnect_channex ]
  before_action :load_salespersons, only: [ :new, :create, :edit, :update ]


  def index
    @all_hotels = Hotel.all.order(created_at: :desc)
    @hotels = @all_hotels.page(params[:page]).per(25)
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
    salesperson_name = salesperson_name_param
    salesperson_email = salesperson_email_param

    ActiveRecord::Base.transaction do
      @hotel.update!(update_hotel_params)
      sync_salesperson_contact!(salesperson_name, salesperson_email)
    end

    redirect_to admin_hotel_path(@hotel), notice: "Hotel updated successfully."
  rescue ActiveRecord::RecordInvalid => e
    @hotel.errors.add(:base, e.record.errors.full_messages.to_sentence) if e.record != @hotel
    render :edit, status: :unprocessable_content
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
    params.require(:hotel).permit(:name, :address, :city, :country, :star_rating, :salesperson_id, :salesperson_name, :salesperson_email, :preferred_channel_manager)
  end

  def account_params
    params.require(:account).permit(:name)
  end

  def user_params
    params.require(:user).permit(:name, :email)
  end

  def load_salespersons
    @salespersons = current_user.account.users.where(role: "salesperson").order(:name)
  end

  def salesperson_name_param
    params.dig(:hotel, :salesperson_name).to_s.strip
  end

  def salesperson_email_param
    params.dig(:hotel, :salesperson_email).to_s.strip
  end

  def sync_salesperson_contact!(salesperson_name, salesperson_email)
    salesperson = @hotel.salesperson

    if salesperson.blank? && salesperson_name.present?
      salesperson = current_user.account.users.find_by(role: "salesperson", name: salesperson_name)
    end

    if salesperson
      updates = {}
      updates[:name] = salesperson_name if salesperson_name.present? && salesperson.name != salesperson_name
      updates[:email] = salesperson_email if salesperson_email.present? && salesperson.email != salesperson_email
      salesperson.update!(updates) if updates.any?
      @hotel.update!(salesperson_id: salesperson.id) if @hotel.salesperson_id != salesperson.id
      return
    end

    return if salesperson_name.blank?

    salesperson = current_user.account.users.create!(
      role: "salesperson",
      name: salesperson_name,
      email: salesperson_email.presence || generated_salesperson_email,
      password: generated_salesperson_password,
      password_confirmation: generated_salesperson_password
    )

    @hotel.update!(salesperson_id: salesperson.id)
  end
end
