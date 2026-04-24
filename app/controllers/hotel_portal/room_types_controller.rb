class HotelPortal::RoomTypesController < HotelPortal::BaseController
  before_action :set_room_type, only: [ :show, :edit, :update, :destroy ]

  def index
    @hotel = current_hotel
    @all_room_types = @hotel.room_types.order(created_at: :desc)
    @room_types = @all_room_types.page(params[:page]).per(25)
    authorize @hotel, :update?, policy_class: HotelPolicy
  end

  def show
    @hotel = current_hotel
    authorize @hotel, :update?, policy_class: HotelPolicy
  end

  def new
    @hotel = current_hotel
    @room_type = @hotel.room_types.build
    authorize @hotel, :update?, policy_class: HotelPolicy
  end

  def create
    @hotel = current_hotel
    @room_type = @hotel.room_types.build(room_type_params)
    authorize @hotel, :update?, policy_class: HotelPolicy

    if @room_type.save
      @hotel.complete_rooms!
      redirect_to hotel_room_types_path(@hotel), notice: "Room type created successfully."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @hotel = current_hotel
    authorize @hotel, :update?, policy_class: HotelPolicy
  end

  def update
    @hotel = current_hotel
    authorize @hotel, :update?, policy_class: HotelPolicy

    if @room_type.update(room_type_params)
      redirect_to hotel_room_types_path(@hotel), notice: "Room type updated successfully."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @hotel = current_hotel
    authorize @hotel, :update?, policy_class: HotelPolicy
    @room_type.destroy
    redirect_to hotel_room_types_path(@hotel), notice: "Room type deleted successfully."
  end

  private

  def set_room_type
    @room_type = current_hotel.room_types.find(params[:id])
  end

  def room_type_params
    params.require(:room_type).permit(:name, :description, :max_adults, :max_children, :quantity, :base_price, photos: [], room_numbers: [])
  end
end
