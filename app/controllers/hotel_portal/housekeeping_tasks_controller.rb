# frozen_string_literal: true

module HotelPortal
  class HousekeepingTasksController < BaseController
    include HousekeepingBoardFilters

    before_action :authorize_housekeeping_board!
    before_action -> { require_feature!("task_assignment_minibar_log") }

    def index
      @staff_members = HotelPortal::ActiveHousekeepersQuery.new(hotel: current_hotel).call
      @selected_date = selected_date
      @room_groups = board

      respond_to do |format|
        format.html { @room_groups = presented(@room_groups) }
        format.pdf { send_pdf }
        format.xlsx { send_excel }
        format.csv { send_csv }
      end
    end

    def assign
      HousekeepingTasks::AssignStaff.new(
        hotel: current_hotel,
        request_id: params[:id],
        assigned_to_id: params[:assigned_to],
        current_user: current_user
      ).call

      respond_to do |format|
        format.html { redirect_to board_return_path, notice: "Task assigned successfully." }
        format.json { render json: { ok: true } }
      end
    end

    # Starting and completing a task is the housekeeper's own job, so it is gated
    # on the board's permissions and answered here. The Requests page has its own
    # route onto the same updater, gated on managing requests, which is a
    # different job done by different people.
    def update_status
      updater = ::HotelPortal::Requests::StatusUpdater.new(
        hotel: current_hotel,
        kind: :housekeeping,
        request_id: params[:id],
        status: params[:status]
      )

      redirect_target = safe_redirect_target(board_return_path)
      if (request = updater.call)
        respond_to do |format|
          format.html { redirect_to redirect_target, notice: "Task updated successfully." }
          format.json { render json: { ok: true, status: request.status } }
        end
      else
        respond_to do |format|
          format.html { redirect_to redirect_target, alert: "Failed to update task." }
          format.json { render json: { ok: false }, status: :unprocessable_entity }
        end
      end
    end

    private

    # A board is always for some date, and a date nobody can read is today.
    def selected_date
      Date.parse(params[:date].to_s)
    rescue ArgumentError, TypeError
      Date.current
    end

    def board
      HousekeepingTasks::BoardBuilder.new(
        hotel: current_hotel,
        date: @selected_date,
        query: params[:q],
        assigned_to: params[:assigned_to],
        room_status: params[:room_status]
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
          rooms: group[:rooms].map { |room| HousekeepingTaskRoomPresenter.new(room, hotel: current_hotel, view_context: context) }
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

    # Dispatchers hand work to anyone, so they get the staff menu; performers can
    # only take and release their own, so they get a single Take/Release button.
    # AssignStaff enforces this regardless -- this only picks the affordance.
    def dispatch_housekeeping?
      return @dispatch_housekeeping if defined?(@dispatch_housekeeping)

      @dispatch_housekeeping = current_user.has_permission?("dispatch_housekeeping_tasks", hotel: current_hotel)
    end
    helper_method :dispatch_housekeeping?
  end
end
