# frozen_string_literal: true

class HotelPortal::RoomTypesController < HotelPortal::BaseController
  before_action :set_hotel
  before_action :authorize_hotel
  before_action :set_room_type, only: [ :show, :edit, :update, :destroy, :destroy_photo, :bulk_destroy_photos ]

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
    if @room_type.destroy
      redirect_to hotel_room_types_path(@hotel), notice: "Room type deleted successfully."
    else
      redirect_to hotel_room_types_path(@hotel), alert: "Cannot delete room type: #{@room_type.errors.full_messages.to_sentence}"
    end
  end

  def destroy_photo
    result = HotelPortal::RoomTypes::DestroyPhotos.new(
      room_type: @room_type,
      photo_ids: [ params[:photo_id] ]
    ).call

    if result.success?
      redirect_to edit_hotel_room_type_path(@hotel, @room_type), notice: result.message
    else
      redirect_to edit_hotel_room_type_path(@hotel, @room_type), alert: result.message
    end
  end

  def bulk_destroy_photos
    result = HotelPortal::RoomTypes::DestroyPhotos.new(
      room_type: @room_type,
      photo_ids: params[:photo_ids]
    ).call

    if result.success?
      redirect_to edit_hotel_room_type_path(@hotel, @room_type), notice: result.message
    else
      redirect_to edit_hotel_room_type_path(@hotel, @room_type), alert: result.message
    end
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
    params.require(:room_type).permit(:name, :description, :max_adults, :max_children, :quantity, :base_price, :room_number_mode, :smoking_allowed, :pets_allowed, photos: [], room_numbers: [], amenities: [])
  end
end
