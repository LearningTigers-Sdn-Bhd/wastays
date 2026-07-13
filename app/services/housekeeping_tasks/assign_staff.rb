# frozen_string_literal: true

module HousekeepingTasks
  class AssignStaff
    def initialize(hotel:, request_id:, assigned_to_id:, current_user:)
      @hotel = hotel
      @request_id = request_id
      @assigned_to_id = assigned_to_id.presence
      @current_user = current_user
    end

    def call
      @request = HousekeepingRequest.left_joins(:booking)
                                    .where("housekeeping_requests.hotel_id = :hotel_id OR bookings.hotel_id = :hotel_id", hotel_id: @hotel.id)
                                    .find(@request_id)

      room_number = @request.room_number.presence
      room_number ||= @request.booking&.booking_rooms&.where.not(room_number: [ nil, "" ])&.first&.room_number.presence

      active_requests = []
      if room_number.present?
        active_requests = HousekeepingRequest.left_joins(booking: :booking_rooms)
                                             .where("housekeeping_requests.hotel_id = :hotel_id OR bookings.hotel_id = :hotel_id", hotel_id: @hotel.id)
                                             .where(
                                               "housekeeping_requests.room_number = :room_number OR (housekeeping_requests.room_number IS NULL AND booking_rooms.room_number = :room_number)",
                                               room_number: room_number
                                             )
                                             .where.not(status: %w[pending completed failed cancelled])
                                             .distinct
                                             .to_a
      end

      active_requests = [ @request ] if active_requests.empty?

      real_active = active_requests.reject { |r| r.status == "no_task" }
      active_requests = real_active if real_active.any?

      active_requests.each do |req|
        req_metadata = req.metadata.to_h
        req_status = req.status

        if @assigned_to_id
          staff = find_housekeeper
          if staff
            if req_metadata["assigned_to"] != staff.id
              history = Array(req_metadata["assignment_history"])
              history << {
                "assigned_to_id" => staff.id,
                "assigned_to_name" => staff.name,
                "assigned_by_id" => @current_user.id,
                "assigned_by_name" => @current_user.name,
                "timestamp" => Time.current.iso8601
              }
              req_metadata["assignment_history"] = history
            end
            req_metadata["assigned_to"] = staff.id
            req_metadata["assigned_to_name"] = staff.name
            req_status = "assigned" if req_status.in?(%w[new no_task])
          else
            req_metadata, req_status = unassign_metadata(req_metadata, req_status)
          end
        else
          req_metadata, req_status = unassign_metadata(req_metadata, req_status)
        end

        req.update!(metadata: req_metadata, status: req_status)
      end
    end

    private

    def find_housekeeper
      HotelPortal::ActiveHousekeepersQuery.new(hotel: @hotel).call.find_by(id: @assigned_to_id)
    end

    def unassign_metadata(metadata, status)
      if metadata["assigned_to"].present?
        history = Array(metadata["assignment_history"])
        history << {
          "assigned_to_name" => "Unassigned",
          "assigned_by_id" => @current_user.id,
          "assigned_by_name" => @current_user.name,
          "timestamp" => Time.current.iso8601
        }
        metadata["assignment_history"] = history
      end
      metadata.delete("assigned_to")
      metadata.delete("assigned_to_name")
      status = "new" if status == "assigned"
      [ metadata, status ]
    end
  end
end
