# frozen_string_literal: true

# Room groups are managed entirely inside one Sheet: the list, the "add group"
# form, and per-group rename all render from `index`. There is no separate edit
# screen — a failed save re-renders the same sheet with the offending row open.
class HotelPortal::RoomGroupsController < HotelPortal::BaseController
  include SheetActionCompletion

  before_action :set_hotel
  before_action :authorize_hotel
  before_action :set_room_group, only: [ :update, :destroy ]

  def index
    render_sheet
  end

  def create
    @new_room_group = @hotel.room_groups.build(room_group_params)

    if @new_room_group.save
      finish_sheet("Room group created successfully.")
    else
      render_sheet(status: :unprocessable_content)
    end
  end

  def update
    if @room_group.update(room_group_params)
      finish_sheet("Room group updated successfully.")
    else
      render_sheet(status: :unprocessable_content)
    end
  end

  def destroy
    if @room_group.destroy
      finish_sheet("Room group deleted successfully.")
    else
      respond_to do |format|
        format.html { redirect_to destination_path, alert: "Cannot delete room group." }
        format.turbo_stream do
          render turbo_stream: toast_stream(
            "Cannot delete room group: #{@room_group.errors.full_messages.to_sentence}",
            type: :error
          ), status: :unprocessable_content
        end
      end
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

  # `@room_group` carries the unsaved attributes of a failed rename so the view
  # can substitute it into the list; `@new_room_group` backs the add form.
  def render_sheet(status: :ok)
    @room_groups = @hotel.room_groups.includes(:room_types).order(:name)
    @new_room_group ||= @hotel.room_groups.build
    render :index, layout: false, status: status
  end

  def finish_sheet(notice)
    complete_sheet_action(destination: destination_path, notice: notice, frame: sheet_frame)
  end

  def sheet_frame
    turbo_frame_request_id.presence || "settings_action_sheet"
  end

  def destination_path
    hotel_room_types_path(@hotel)
  end

  def room_group_params
    params.require(:room_group).permit(:name)
  end
end
