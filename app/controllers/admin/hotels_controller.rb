class Admin::HotelsController < Admin::BaseController
  before_action :set_hotel, only: [ :show, :edit, :update, :approve, :suspend ]
  before_action :load_salespersons, only: [ :new, :create, :edit, :update ]

  def index
    @hotels = Hotel.all.order(created_at: :desc)
  end

  def onboarding_index
    @hotels = Hotel.where(status: ["registered", "email_verified", "profile_incomplete", "rooms_incomplete", "inventory_incomplete", "pending_review"]).order(created_at: :desc)
  end

  def show
    month_to_date_bookings = @hotel.bookings.revenue_generating.where(created_at: Time.current.all_month)

    @gross_revenue_mtd = month_to_date_bookings.sum(:total_amount)
    @wastays_margin_mtd = month_to_date_bookings.sum("COALESCE(margin_amount, 0)")
    @hotel_net_earnings_mtd = month_to_date_bookings.sum("COALESCE(net_amount, 0)")
    @booking_count_mtd = month_to_date_bookings.count
    @configured_margin_rate = @hotel.effective_margin_rate
  end

  def onboarding
    @hotel = Hotel.find(params[:id])
    @tasks = @hotel.onboarding_tasks.order(:created_at)
    @sessions = @hotel.onboarding_sessions.order(scheduled_at: :desc)
    @trainers = User.where(role: ["admin", "superadmin"]).order(:name)
  end

  def create_onboarding_session
    @hotel = Hotel.find(params[:id])
    @session = @hotel.onboarding_sessions.new(onboarding_session_params)
    @session.status = "scheduled"

    if @session.save
      redirect_to onboarding_admin_hotel_path(@hotel), notice: "Training session scheduled successfully."
    else
      redirect_to onboarding_admin_hotel_path(@hotel), alert: "Failed to schedule session: #{@session.errors.full_messages.to_sentence}"
    end
  end

  def complete_onboarding_session
    @hotel = Hotel.find(params[:id])
    @session = @hotel.onboarding_sessions.find(params[:session_id])

    if @session.complete!
      redirect_to onboarding_admin_hotel_path(@hotel), notice: "Training session marked as completed."
    else
      redirect_to onboarding_admin_hotel_path(@hotel), alert: "Failed to update session."
    end
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

  private

  def set_hotel
    @hotel = Hotel.find(params[:id])
  end

  def create_hotel_params
    params.require(:hotel).permit(:name, :address, :city, :country, :star_rating, :salesperson_id).merge(status: "approved")
  end

  def update_hotel_params
    params.require(:hotel).permit(:name, :address, :city, :country, :star_rating, :salesperson_id)
  end

  def account_params
    params.require(:account).permit(:name)
  end

  def user_params
    params.require(:user).permit(:name, :email)
  end

  def onboarding_session_params
    params.permit(:trainer_id, :scheduled_at, :meeting_link)
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
    elsif salesperson_name.present?
      # Create new salesperson if they don't exist
      password = SecureRandom.hex(16)
      salesperson = current_user.account.users.create!(
        role: "salesperson",
        name: salesperson_name,
        email: salesperson_email.presence || "salesperson-#{SecureRandom.hex(6)}@wastays.local",
        password: password,
        password_confirmation: password
      )
    end

    if salesperson && @hotel.salesperson_id != salesperson.id
      @hotel.update!(salesperson_id: salesperson.id)
    end
  end
end
