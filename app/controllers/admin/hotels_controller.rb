class Admin::HotelsController < Admin::BaseController
  before_action :set_hotel, only: [:show, :edit, :update, :approve, :suspend]

  def index
    @hotels = Hotel.all.order(created_at: :desc)
  end

  def show
  end

  def new
    @hotel = Hotel.new
  end

  def create
    @hotel = Hotel.new(hotel_params)
    @hotel.status ||= 'approved' # Default to approved for admin-created hotels
    
    # Simple logic: Assign to first account if not specified
    @hotel.account ||= Account.first || Account.create!(name: "Default Account", status: "active")

    if @hotel.save
      redirect_to admin_hotel_path(@hotel), notice: "Hotel created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @hotel.update(hotel_params)
      redirect_to admin_hotel_path(@hotel), notice: "Hotel updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def approve
    if @hotel.update(status: 'approved')
      redirect_to admin_hotel_path(@hotel), notice: "Hotel has been approved."
    else
      redirect_to admin_hotel_path(@hotel), alert: "Failed to approve hotel."
    end
  end

  def suspend
    if @hotel.update(status: 'suspended')
      redirect_to admin_hotel_path(@hotel), notice: "Hotel has been suspended."
    else
      redirect_to admin_hotel_path(@hotel), alert: "Failed to suspend hotel."
    end
  end

  private

  def set_hotel
    @hotel = Hotel.find(params[:id])
  end

  def hotel_params
    params.require(:hotel).permit(:name, :address, :city, :country, :star_rating, :status, :account_id)
  end
end
