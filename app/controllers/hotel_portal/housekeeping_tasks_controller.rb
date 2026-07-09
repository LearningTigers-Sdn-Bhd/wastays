# frozen_string_literal: true

module HotelPortal
  class HousekeepingTasksController < BaseController
    before_action :authorize_manage_requests!
    before_action -> { require_feature!("task_assignment_minibar_log") }

    def index
      @staff_members = current_hotel.users.joins(:roles).where(roles: { slug: "housekeeper" }).order(:name).distinct
      @staff_members = current_hotel.users.order(:name) if @staff_members.empty?

      # Build room groups with resolved statuses, active bookings, and tasks
      @room_groups = current_hotel.room_types.order(:name).map do |room_type|
        rooms_list = room_type.room_numbers.map do |room_number|
          resolved = Rooms::StatusResolver.new(
            hotel: current_hotel,
            room_type: room_type,
            room_number: room_number,
            date: Date.current
          ).call

          active_booking = resolved.booking_details&.dig(:active)&.first || resolved.booking_details&.dig(:completed)&.first

          hk_request = HousekeepingRequest.joins(:booking)
                                          .where(bookings: { hotel_id: current_hotel.id }, room_number: room_number, status: "in_progress")
                                          .first

          {
            room_number: room_number,
            room_type: room_type,
            resolved_status: resolved.status,
            active_booking: active_booking,
            hk_request: hk_request
          }
        end

        {
          room_type: room_type,
          rooms: rooms_list
        }
      end

      # Filter by room number
      if params[:room_number].present?
        @room_groups.each do |group|
          group[:rooms].select! { |r| r[:room_number].to_s == params[:room_number].to_s }
        end
        @room_groups.select! { |group| group[:rooms].any? }
      end

      # Filter by search query
      if params[:q].present?
        q = params[:q].downcase
        @room_groups.each do |group|
          group[:rooms].select! do |r|
            r[:room_number].to_s.downcase.include?(q) ||
              group[:room_type].name.downcase.include?(q) ||
              (r[:active_booking] && (r[:active_booking].guest_name.to_s.downcase.include?(q) || r[:active_booking].confirmation_token.to_s.downcase.include?(q))) ||
              (r[:hk_request] && r[:hk_request].request_details.to_s.downcase.include?(q))
          end
        end
        @room_groups.select! { |group| group[:rooms].any? }
      end
    end

    def assign
      @request = HousekeepingRequest.joins(:booking)
                                    .where(bookings: { hotel_id: current_hotel.id })
                                    .find(params[:id])

      assigned_to = params[:assigned_to].presence
      metadata = @request.metadata.to_h

      if assigned_to
        staff = current_hotel.users.joins(:roles).where(roles: { slug: "housekeeper" }).find_by(id: assigned_to)
        staff ||= current_hotel.users.find_by(id: assigned_to) # fallback
        if staff
          metadata["assigned_to"] = staff.id
          metadata["assigned_to_name"] = staff.name
        else
          metadata.delete("assigned_to")
          metadata.delete("assigned_to_name")
        end
      else
        metadata.delete("assigned_to")
        metadata.delete("assigned_to_name")
      end

      @request.update!(metadata: metadata)

      respond_to do |format|
        format.html { redirect_to hotel_room_status_board_path(current_hotel, tab: "housekeeping"), notice: "Task assigned successfully." }
        format.json { render json: { ok: true } }
      end
    end

    private

    def authorize_manage_requests!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_requests", hotel: current_hotel)
    end
  end
end
