class Admin::HotelsController < Admin::BaseController
  before_action :set_hotel, only: [ :show, :edit, :update, :approve, :suspend ]

  def index
    @hotels = Hotel.all.order(created_at: :desc)
  end

  def show
  end

  def new
    @hotel = Hotel.new
  end

  def create
    @hotel = Hotel.new(create_hotel_params)
    @hotel.account = selected_account || default_account
    @hotel.status ||= "approved"

    if @hotel.save
      redirect_to admin_hotel_path(@hotel), notice: "Hotel created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @hotel.update(update_hotel_params)
      redirect_to admin_hotel_path(@hotel), notice: "Hotel updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def approve
    if @hotel.update(status: "approved")
      redirect_to admin_hotel_path(@hotel), notice: "Hotel has been approved."
    else
      redirect_to admin_hotel_path(@hotel), alert: "Failed to approve hotel."
    end
  end

  def suspend
    if @hotel.update(status: "suspended")
      redirect_to admin_hotel_path(@hotel), notice: "Hotel has been suspended."
    else
      redirect_to admin_hotel_path(@hotel), alert: "Failed to suspend hotel."
    end
  end

  private

  def set_hotel
    @hotel = Hotel.find(params[:id])
  end

  def create_hotel_params
    params.require(:hotel).permit(:name, :address, :city, :country, :star_rating, :status)
  end

  def update_hotel_params
    create_hotel_params
  end

  def selected_account
    account_id = params.dig(:hotel, :account_id).presence
    Account.find_by(id: account_id) if account_id
  end

  def default_account
    Account.first || Account.create!(name: "Default Account", status: "active")
  end
end
