# frozen_string_literal: true

class HotelPortal::RoomTypesController < HotelPortal::BaseController
  before_action :set_hotel
  before_action :authorize_hotel
  before_action :set_room_type, only: [ :show, :edit, :update, :destroy ]

  def index
    @all_room_types = RoomTypesQuery.new(@hotel.room_types).call(params)
    @room_types = @all_room_types.page(params[:page]).per(25)
  end

  def show; end

  def new
    @room_type = @hotel.room_types.build
  end

  def create
    result = HotelPortal::RoomTypes::SaveRoomType.new(
      hotel: @hotel,
      params: room_type_params
    ).call

    if result.success?
      redirect_to hotel_room_types_path(@hotel), notice: "Room type created successfully."
    else
      @room_type = result.room_type
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    result = HotelPortal::RoomTypes::SaveRoomType.new(
      hotel: @hotel,
      room_type: @room_type,
      params: room_type_params
    ).call

    if result.success?
      redirect_to hotel_room_types_path(@hotel), notice: "Room type updated successfully."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @room_type.destroy
    redirect_to hotel_room_types_path(@hotel), notice: "Room type deleted successfully."
  end

  private

  def set_hotel
    @hotel = current_hotel
  end

  def authorize_hotel
    authorize @hotel, :update?, policy_class: HotelPolicy
  end

  def set_room_type
    @room_type = @hotel.room_types.find(params[:id])
  end

  def room_type_params
    params.require(:room_type).permit(:name, :description, :max_adults, :max_children, :quantity, :base_price, :room_number_mode, photos: [], room_numbers: [], amenities: [])
  end
end
