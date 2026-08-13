# frozen_string_literal: true

class HotelPortal::RoomGroupsController < HotelPortal::SettingsBaseController
  include SheetActionCompletion

  before_action :set_hotel
  before_action :authorize_hotel
  before_action :set_room_group, only: %i[edit update destroy]

  def index
    @room_groups = @hotel.room_groups.includes(:room_types).order(:name, :id)
  end

  def new
    @room_group = @hotel.room_groups.build
    render layout: false
  end

  def create
    result = HotelPortal::RoomGroups::Save.call(hotel: @hotel, attributes: room_group_params)
    @room_group = result.room_group

    if result.success?
      finish_sheet("Room group created successfully.")
    else
      render :new, layout: false, status: :unprocessable_content
    end
  end

  def edit
    render layout: false
  end

  def update
    result = HotelPortal::RoomGroups::Save.call(
      hotel: @hotel,
      room_group: @room_group,
      attributes: room_group_params
    )

    if result.success?
      finish_sheet("Room group updated successfully.")
    else
      render :edit, layout: false, status: :unprocessable_content
    end
  end

  def destroy
    if @room_group.destroy
      redirect_to hotel_room_groups_path(@hotel), notice: "Room group deleted successfully."
    else
      redirect_to hotel_room_groups_path(@hotel),
                  alert: "Cannot delete room group: #{@room_group.errors.full_messages.to_sentence}"
    end
  end

  private

  def set_hotel
    @hotel = current_hotel
  end

  def authorize_hotel
    authorize @hotel, :update?, policy_class: HotelPolicy
  end

  def set_room_group
    @room_group = @hotel.room_groups.find(params[:id])
  end

  def room_group_params
    params.require(:room_group).permit(:name)
  end

  def finish_sheet(notice)
    complete_sheet_action(
      destination: hotel_room_groups_path(@hotel),
      notice: notice,
      frame: turbo_frame_request_id.presence || "settings_action_sheet"
    )
  end
end
