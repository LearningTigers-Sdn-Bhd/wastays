# frozen_string_literal: true

module HotelPortal
  class HousekeepingTasksController < BaseController
    before_action :authorize_manage_housekeeping_tasks!
    before_action -> { require_feature!("task_assignment_minibar_log") }

    def index
      @staff_members = HotelPortal::ActiveHousekeepersQuery.new(hotel: current_hotel).call

      @selected_date = Date.current
      if params[:date].present?
        begin
          @selected_date = Date.parse(params[:date].to_s)
        rescue ArgumentError, TypeError
          # fallback to Date.current
        end
      end

      @room_groups = HousekeepingTasks::BoardBuilder.new(
        hotel: current_hotel,
        date: @selected_date,
        params: params
      ).call

      respond_to do |format|
        format.html do
          @room_groups = @room_groups.map do |group|
            {
              room_type: group[:room_type],
              rooms: group[:rooms].map { |room| HousekeepingTaskRoomPresenter.new(room, current_hotel) }
            }
          end
        end
        format.pdf do
          send_data ::Reports::HousekeepingTasksPdfGenerator.new(
            hotel: current_hotel,
            room_groups: @room_groups,
            selected_date: @selected_date
          ).call,
          filename: "housekeeping-tasks-#{@selected_date}.pdf",
          type: "application/pdf"
        end
        format.xls do
          send_data ::Reports::HousekeepingTasksXlsGenerator.new(
            hotel: current_hotel,
            room_groups: @room_groups
          ).call,
          filename: "housekeeping-tasks-#{@selected_date}.xls",
          type: "application/vnd.ms-excel"
        end
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
        format.html { redirect_to hotel_housekeeping_tasks_path(current_hotel), notice: "Task assigned successfully." }
        format.json { render json: { ok: true } }
      end
    end

    private

    def authorize_manage_housekeeping_tasks!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_housekeeping_tasks", hotel: current_hotel)
    end
  end
end
