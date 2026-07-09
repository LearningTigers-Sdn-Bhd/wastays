# frozen_string_literal: true

module HotelPortal
  class HousekeepingTasksController < BaseController
    before_action :authorize_manage_requests!
    before_action -> { require_feature!("task_assignment_minibar_log") }

    def index
      @staff_members = User.where(id: UserHotelAccess.active
                                                     .where(hotel_id: current_hotel.id)
                                                     .joins(:role)
                                                     .where(roles: { slug: "housekeeper" })
                                                     .select(:user_id))
                           .order(:name)

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

          hk_requests = HousekeepingRequest.left_joins(booking: :booking_rooms)
                                           .where("housekeeping_requests.hotel_id = :hotel_id OR bookings.hotel_id = :hotel_id", hotel_id: current_hotel.id)
                                           .where(
                                             "housekeeping_requests.room_number = :room_number OR (housekeeping_requests.room_number IS NULL AND booking_rooms.room_number = :room_number)",
                                             room_number: room_number
                                           )
                                           .where.not(status: %w[pending completed failed cancelled])
                                           .distinct
                                           .to_a
                                           .sort_by { |r| [ r.status == "no_task" ? 1 : 0, -r.created_at.to_i ] }

          real_requests = hk_requests.reject { |r| r.status == "no_task" }
          if real_requests.any?
            hk_requests = real_requests
          elsif hk_requests.empty?
            placeholder = HousekeepingRequest.create!(
              hotel: current_hotel,
              room_type: room_type,
              room_number: room_number,
              booking: active_booking,
              status: "no_task",
              request_details: "-",
              requested_at: Time.current
            )
            hk_requests = [ placeholder ]
          end

          {
            room_number: room_number,
            room_type: room_type,
            resolved_status: resolved.status,
            active_booking: active_booking,
            hk_requests: hk_requests
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
      @request = HousekeepingRequest.left_joins(:booking)
                                    .where("housekeeping_requests.hotel_id = :hotel_id OR bookings.hotel_id = :hotel_id", hotel_id: current_hotel.id)
                                    .find(params[:id])

      assigned_to = params[:assigned_to].presence

      # Resolve room number, falling back to the booking's rooms if the request doesn't have it directly
      room_number = @request.room_number.presence
      room_number ||= @request.booking&.booking_rooms&.where.not(room_number: [nil, ""])&.first&.room_number.presence

      active_requests = []
      if room_number.present?
        active_requests = HousekeepingRequest.left_joins(booking: :booking_rooms)
                                             .where("housekeeping_requests.hotel_id = :hotel_id OR bookings.hotel_id = :hotel_id", hotel_id: current_hotel.id)
                                             .where(
                                               "housekeeping_requests.room_number = :room_number OR (housekeeping_requests.room_number IS NULL AND booking_rooms.room_number = :room_number)",
                                               room_number: room_number
                                             )
                                             .where.not(status: %w[pending completed failed cancelled])
                                             .distinct
                                             .to_a
      end

      if active_requests.empty?
        active_requests = [@request]
      end

      # Reject any placeholder "no_task" requests if there are other active real requests
      real_active = active_requests.reject { |r| r.status == "no_task" }
      if real_active.any?
        active_requests = real_active
      end

      active_requests.each do |req|
        req_metadata = req.metadata.to_h
        req_status = req.status

        if assigned_to
          staff = User.where(id: UserHotelAccess.active
                                                 .where(hotel_id: current_hotel.id)
                                                 .joins(:role)
                                                 .where(roles: { slug: "housekeeper" })
                                                 .select(:user_id))
                      .find_by(id: assigned_to)
          if staff
            req_metadata["assigned_to"] = staff.id
            req_metadata["assigned_to_name"] = staff.name
            if req_status.in?(%w[new no_task])
              req_status = "assigned"
            end
          else
            req_metadata.delete("assigned_to")
            req_metadata.delete("assigned_to_name")
            if req_status == "assigned"
              req_status = "new"
            end
          end
        else
          req_metadata.delete("assigned_to")
          req_metadata.delete("assigned_to_name")
          if req_status == "assigned"
            req_status = "new"
          end
        end

        req.update!(metadata: req_metadata, status: req_status)
      end

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
