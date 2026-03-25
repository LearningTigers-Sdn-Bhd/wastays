class Hotel::RoomTypesController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_hotel_access!
  before_action :set_room_type, only: [:edit, :update, :destroy]

  def index
    @room_types = current_hotel.room_types
    authorize current_hotel, :update?, policy_class: HotelPolicy
  end

  def new
    @room_type = current_hotel.room_types.build
    authorize current_hotel, :update?, policy_class: HotelPolicy
  end

  def create
    @room_type = current_hotel.room_types.build(room_type_params)
    authorize current_hotel, :update?, policy_class: HotelPolicy

    if @room_type.save
      current_hotel.complete_rooms!
      redirect_to hotel_room_types_path, notice: "Room type created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize current_hotel, :update?, policy_class: HotelPolicy
  end

  def update
    authorize current_hotel, :update?, policy_class: HotelPolicy

    if @room_type.update(room_type_params)
      redirect_to hotel_room_types_path, notice: "Room type updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize current_hotel, :update?, policy_class: HotelPolicy
    @room_type.destroy
    redirect_to hotel_room_types_path, notice: "Room type deleted successfully."
  end

  private

  def set_room_type
    @room_type = current_hotel.room_types.find(params[:id])
  end

  def room_type_params
    params.require(:room_type).permit(:name, :description, :max_adults, :max_children, :quantity, :base_price, photos: [])
  end
end
