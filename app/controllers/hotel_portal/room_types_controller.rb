# frozen_string_literal: true

class HotelPortal::RoomTypesController < HotelPortal::SettingsBaseController
  include SheetActionCompletion

  before_action :set_hotel
  before_action :authorize_hotel
  before_action :set_room_type, only: [ :edit, :update, :destroy, :destroy_photo, :bulk_destroy_photos ]

  def index
    room_types = @hotel.room_types.includes(
      :room_group,
      room_type_rate_plans: [ :channel_mapping, :occupancy_prices, :rate_plan ]
    )
    @all_room_types = RoomTypesQuery.new(room_types).call(params)
    @room_types = @all_room_types.page(params[:page]).per(25)

    @room_groups = @hotel.room_groups.order(:name)
    @selected_room_group_ids = Array(params[:room_group_ids]).compact_blank.map(&:to_s)
    @filters_active = params[:q].present? || @selected_room_group_ids.any?
  end

  def new
    @room_type = @hotel.room_types.build
    render layout: false
  end

  def create
    result = HotelPortal::RoomTypes::SaveRoomType.new(
      hotel: @hotel,
      params: room_type_params
    ).call

    if result.success?
      finish_sheet("Room category created successfully.")
    else
      @room_type = result.room_type
      render :new, layout: false, status: :unprocessable_content
    end
  end

  def edit
    render layout: false
  end

  def update
    result = HotelPortal::RoomTypes::SaveRoomType.new(
      hotel: @hotel,
      room_type: @room_type,
      params: room_type_params
    ).call

    if result.success?
      finish_sheet("Room category updated successfully.")
    else
      render :edit, layout: false, status: :unprocessable_content
    end
  end

  def destroy
    result = HotelPortal::RoomTypes::DestroyRoomType.new(room_type: @room_type).call

    if result.success?
      redirect_to hotel_room_types_path(@hotel), notice: "Room type deleted successfully."
    else
      redirect_to hotel_room_types_path(@hotel), alert: "Cannot delete room type: #{result.errors.full_messages.to_sentence}"
    end
  end

  def destroy_photo
    result = HotelPortal::RoomTypes::DestroyPhotos.new(
      room_type: @room_type,
      photo_ids: [ params[:photo_id] ]
    ).call

    respond_to_photo_removal(result)
  end

  def bulk_destroy_photos
    result = HotelPortal::RoomTypes::DestroyPhotos.new(
      room_type: @room_type,
      photo_ids: params[:photo_ids]
    ).call

    respond_to_photo_removal(result)
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

  # Photos are deleted from inside the open form sheet, so only the photo grid is
  # re-rendered: a redirect would rebuild the whole sheet and throw away
  # everything the operator had typed but not yet saved.
  def respond_to_photo_removal(result)
    @room_type.photos.reload

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("room-type-photos-manager", partial: "hotel_portal/room_types/photo_manager", locals: { room_type: @room_type }),
          toast_stream(result.message, type: result.success? ? :success : :error)
        ], status: (result.success? ? :ok : :unprocessable_content)
      end
      format.html do
        redirect_to hotel_room_types_path(@hotel),
                    notice: (result.message if result.success?),
                    alert: (result.message unless result.success?)
      end
    end
  end

  def finish_sheet(notice)
    complete_sheet_action(destination: hotel_room_types_path(@hotel), notice: notice, frame: sheet_frame)
  end

  def sheet_frame
    turbo_frame_request_id.presence || "settings_action_sheet"
  end

  def room_type_params
    params.require(:room_type).permit(:name, :description, :max_adults, :max_children, :quantity, :base_price, :room_number_mode, :smoking_allowed, :pets_allowed, :room_group_id, photos: [], room_numbers: [], amenities: [])
  end
end
