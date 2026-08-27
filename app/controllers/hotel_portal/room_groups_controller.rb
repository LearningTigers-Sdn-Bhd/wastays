# frozen_string_literal: true

require "ostruct"

class HotelPortal::RoomGroupsController < HotelPortal::SettingsBaseController
  include SheetActionCompletion

  before_action :set_hotel
  before_action :authorize_hotel
  before_action :set_room_group, only: %i[edit update destroy]

  def index
    @room_groups = @hotel.room_groups.includes(active_rooms: :room_type).order(:name, :id)
    @unassigned_room_count = @hotel.rooms.active.where(room_group_id: nil).count
  end

  def new
    @room_group = @hotel.room_groups.build
    load_room_form_state
    render layout: false
  end

  def create
    attributes = room_group_params
    result = HotelPortal::RoomGroups::Save.call(hotel: @hotel, attributes: attributes)
    @room_group = result.room_group

    if result.success?
      finish_sheet("Room group created successfully.")
    else
      load_room_form_state(selected_room_ids: attributes[:room_ids])
      render :new, layout: false, status: :unprocessable_content
    end
  end

  def edit
    load_room_form_state(selected_room_ids: @room_group.active_room_ids)
    render layout: false
  end

  def update
    attributes = room_group_params
    result = HotelPortal::RoomGroups::Save.call(
      hotel: @hotel,
      room_group: @room_group,
      attributes: attributes
    )

    if result.success?
      finish_sheet("Room group updated successfully.")
    else
      load_room_form_state(selected_room_ids: attributes[:room_ids])
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
    params.require(:room_group).permit(:name, room_ids: [])
  end

  def load_room_form_state(selected_room_ids: [])
    rooms = @hotel.rooms.active.includes(:room_group, :room_type)
    rooms = if @room_group.persisted?
      rooms.where(room_group_id: [ nil, @room_group.id ])
    else
      rooms.where(room_group_id: nil)
    end
    @rooms = rooms.references(:room_type).order("room_types.name ASC", :position, :number, :id).to_a
    @room_types = @rooms.map(&:room_type).uniq
    @selected_room_ids = Array(selected_room_ids).compact_blank.map(&:to_s)
  end

  def finish_sheet(notice)
    complete_sheet_action(
      destination: hotel_room_groups_path(@hotel),
      notice: notice,
      frame: turbo_frame_request_id.presence || "settings_action_sheet"
    )
  end
end
