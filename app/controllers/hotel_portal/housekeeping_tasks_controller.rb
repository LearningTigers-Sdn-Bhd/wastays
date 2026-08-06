# frozen_string_literal: true

module HotelPortal
  class HousekeepingTasksController < BaseController
    include HousekeepingBoardFilters
    include HousekeepingTaskAuthorization

    before_action :authorize_housekeeping_board!
    before_action -> { require_feature!("task_assignment_minibar_log") }

    def index
      @staff_members = HotelPortal::ActiveHousekeepersQuery.new(hotel: current_hotel).call
      @room_types = current_hotel.room_types.order(:name).to_a
      @selected_date = selected_date
      @room_groups = board

      respond_to do |format|
        format.html { @room_groups = presented(@room_groups) }
        format.pdf { send_pdf }
        format.xlsx { send_excel }
        format.csv { send_csv }
      end
    end

    def update_room_assignment
      result = HousekeepingTasks::AssignRoom.new(
        hotel: current_hotel,
        room_type_id: params[:room_type_id],
        room_number: params[:room_number],
        date: mutation_date,
        assigned_to_id: params[:assigned_to_id],
        current_user: current_user
      ).call

      respond_with_room_result(result, success_notice: "Housekeeping assignment updated.")
    end

    def update_room_status
      result = HousekeepingTasks::UpdateRoomStatus.new(
        hotel: current_hotel,
        room_type_id: params[:room_type_id],
        room_number: params[:room_number],
        date: mutation_date,
        status: params[:status],
        notes: params[:notes],
        current_user: current_user
      ).call

      respond_with_room_result(result, success_notice: "Room status updated.")
    end

    def edit_remarks
      unless current_housekeeping_date?
        return redirect_to board_return_path, alert: "Housekeeping can only be updated for the current business date."
      end

      @room_type = current_hotel.room_types.find(params[:room_type_id])
      @room_number = params[:room_number].to_s.strip
      raise ActiveRecord::RecordNotFound unless @room_type.room_numbers.include?(@room_number)

      @room_status = current_hotel.room_statuses.find_or_initialize_by(room_type: @room_type, room_number: @room_number)
      @selected_date = Date.parse(mutation_date.to_s)
      @return_to = housekeeping_return_to
      render "hotel_portal/housekeeping_tasks/remarks/edit", layout: false
    end

    def update_remarks
      result = HousekeepingTasks::UpdateRoomRemarks.new(
        hotel: current_hotel,
        room_type_id: params[:room_type_id],
        room_number: params[:room_number],
        date: mutation_date,
        notes: params[:notes],
        current_user: current_user
      ).call

      respond_with_room_result(result, success_notice: "Housekeeping remarks updated.")
    end

    private

    def mutation_date
      params[:date].presence || current_hotel.current_business_date || current_hotel.business_date_for(Time.current)
    end

    def current_housekeeping_date?
      Date.parse(mutation_date.to_s) == (current_hotel.current_business_date || current_hotel.business_date_for(Time.current)).to_date
    rescue Date::Error, TypeError
      false
    end

    def housekeeping_return_to
      candidate = params[:return_to].to_s
      return board_return_path unless candidate.start_with?("/")
      return board_return_path if candidate.start_with?("//")

      candidate
    end

    def respond_with_room_result(result, success_notice:)
      redirect_target = housekeeping_return_to
      respond_to do |format|
        if result.success?
          format.html { redirect_to redirect_target, notice: success_notice }
          format.json { render json: { ok: true, room_status: result.try(:room_status)&.status } }
        else
          format.html { redirect_to redirect_target, alert: result.error }
          format.json { render json: { ok: false, error: result.error }, status: :unprocessable_content }
        end
      end
    end

    # The board is intentionally limited to the hotel's current business date.
    def selected_date
      current_hotel.current_business_date || current_hotel.business_date_for(Time.current)
    end

    def board
      filters = board_filters

      HousekeepingTasks::BoardBuilder.new(
        hotel: current_hotel,
        date: @selected_date,
        room_type_ids: filters[:room_type_ids],
        room_statuses: filters[:room_statuses],
        assigned_to_ids: filters[:assigned_to_ids],
        booking_statuses: filters[:booking_statuses],
        sort: filters[:sort],
        direction: filters[:direction]
      ).call
    end

    # Only the page needs presenters; the exports read the board itself. One view
    # context is built here and handed down, rather than each presenter reaching
    # for Rails to format a date or name a path.
    def presented(room_groups)
      context = view_context

      room_groups.map do |group|
        {
          room_type: group[:room_type],
          rooms: group[:rooms].map do |room|
            HousekeepingTaskRoomPresenter.new(
              room,
              hotel: current_hotel,
              view_context: context,
              selected_date: @selected_date
            )
          end
        }
      end
    end

    def send_pdf
      send_data ::Reports::HousekeepingTasksPdfGenerator.new(
        hotel: current_hotel, room_groups: @room_groups, selected_date: @selected_date
      ).call, filename: export_filename("pdf"), type: "application/pdf"
    end

    def send_excel
      send_data ::Reports::HousekeepingTasksExcelGenerator.new(
        hotel: current_hotel, room_groups: @room_groups, selected_date: @selected_date
      ).call, filename: export_filename("xlsx"),
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    end

    def send_csv
      send_data ::Reports::HousekeepingTasksCsvGenerator.new(room_groups: @room_groups).call,
        filename: export_filename("csv"), type: "text/csv; charset=utf-8"
    end

    def export_filename(extension)
      "housekeeping-tasks-#{@selected_date}.#{extension}"
    end

    # The board itself is readable by anyone who works housekeeping. Who may
    # assign whom is enforced further in, by HousekeepingTasks::AssignStaff.
    def authorize_housekeeping_board!
      allowed = current_user.has_permission?("perform_housekeeping_tasks", hotel: current_hotel) ||
                current_user.has_permission?("dispatch_housekeeping_tasks", hotel: current_hotel)
      raise Pundit::NotAuthorizedError unless allowed
    end
  end
end
