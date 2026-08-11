# frozen_string_literal: true

class HotelPortal::RoomGroupAssignmentsController < HotelPortal::SettingsBaseController
  include SheetActionCompletion

  before_action :set_hotel
  before_action :authorize_hotel

  def new
    load_form_state(selected_room_type_ids: [ params[:room_type_id] ])
    render layout: false
  end

  def create
    attributes = assignment_params
    @assignment = HotelPortal::RoomGroupAssignmentForm.new(attributes)

    result = HotelPortal::RoomGroups::Assign.call(hotel: @hotel, form: @assignment)
    if result.success?
      finish_sheet("Assigned #{helpers.pluralize(Array(@assignment.room_type_ids).compact_blank.size, 'room category')} to #{result.room_group.name}.")
    else
      load_form_state(
        room_group_id: attributes[:room_group_id],
        selected_room_type_ids: attributes[:room_type_ids],
        form: @assignment
      )
      render :new, layout: false, status: :unprocessable_content
    end
  end

  private

  def set_hotel
    @hotel = current_hotel
  end

  def authorize_hotel
    authorize @hotel, :update?, policy_class: HotelPolicy
  end

  def assignment_params
    params.require(:room_group_assignment).permit(:room_group_id, :new_group_name, room_type_ids: [])
  end

  def load_form_state(room_group_id: nil, selected_room_type_ids: [], form: nil)
    @room_groups = @hotel.room_groups.order(:name, :id).to_a
    @room_types = @hotel.room_types.includes(:room_group).order(:name, :id).to_a
    @selected_room_type_ids = Array(selected_room_type_ids).compact_blank.map(&:to_s)
    @assignment = form || HotelPortal::RoomGroupAssignmentForm.new(
      room_group_id: room_group_id,
      room_type_ids: @selected_room_type_ids
    )
  end

  def finish_sheet(notice)
    complete_sheet_action(
      destination: hotel_room_types_path(@hotel),
      notice: notice,
      frame: turbo_frame_request_id.presence || "settings_action_sheet"
    )
  end
end
