# frozen_string_literal: true

class HotelPortal::RoomTypesController < HotelPortal::SettingsBaseController
  include SheetActionCompletion

  before_action :set_hotel
  before_action :authorize_hotel
  before_action :set_room_type, only: [ :edit, :update, :destroy, :destroy_photo, :bulk_destroy_photos, :set_featured_photo, :reorder_photos ]

  def index
    room_types = @hotel.room_types.includes(
      room_type_rate_plans: [ :channel_mapping, :occupancy_prices, :rate_plan ]
    )
    @all_room_types = RoomTypesQuery.new(room_types).call(params)
    @pagy, @room_types = pagy(:offset, @all_room_types, limit: 25)

    @filters_active = params[:q].present?
  end

  def new
    @room_type = @hotel.room_types.build
    set_room_numbering_context
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
      set_room_numbering_context
      render :new, layout: false, status: :unprocessable_content
    end
  end

  def edit
    set_room_numbering_context
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
      set_room_numbering_context
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

  # The featured photo is the cover guests see on the room row and the room card,
  # so it changes from inside the open form sheet like a deletion does: only the
  # photo grid is re-rendered, and nothing typed but unsaved is thrown away.
  def set_featured_photo
    photo = @room_type.photos.attachments.find_by(id: params[:photo_id])

    if photo.blank?
      return render_photo_manager("Photo not found.", success: false, status: :not_found)
    end

    if @room_type.update(featured_photo_attachment_id: photo.id)
      render_photo_manager("Featured photo updated successfully.", success: true)
    else
      render_photo_manager(@room_type.errors.full_messages.to_sentence, success: false)
    end
  end

  # The grid stages its new order in the browser and saves it in one request, so
  # a drag never writes to the database on its own.
  def reorder_photos
    @room_type.reorder_photos!(params[:ordered_ids].to_s.split(","))

    render_photo_manager("Photo order saved successfully.", success: true)
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

    render_photo_manager(result.message, success: result.success?)
  end

  def render_photo_manager(message, success:, status: nil)
    status ||= success ? :ok : :unprocessable_content

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("room-type-photos-manager", partial: "hotel_portal/room_types/photo_manager", locals: { room_type: @room_type }),
          toast_stream(message, type: success ? :success : :error)
        ], status: status
      end
      format.html do
        redirect_to hotel_room_types_path(@hotel),
                    notice: (message if success),
                    alert: (message unless success)
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
    params.require(:room_type).permit(:name, :description, :max_adults, :max_children, :quantity, :base_price, :room_number_mode, :smoking_allowed, :pets_allowed, photos: [], room_numbers: [], amenities: [])
  end

  def set_room_numbering_context
    @room_numbering_context = Rooms::NumberingContext.call(hotel: @hotel, room_type: @room_type)
  end
end
