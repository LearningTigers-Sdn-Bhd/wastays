module HotelPortal
  module Requests
    class StatusUpdater
      attr_reader :hotel, :kind, :request_id, :status, :request

      def initialize(hotel:, kind:, request_id:, status:, trigger_webhook: true)
        @hotel = hotel
        @kind = kind.to_s
        @request_id = request_id
        @status = status.to_s
        @trigger_webhook = trigger_webhook
      end

      def call
        @request = find_request
        target_status = normalize_status
        old_status = @request.status

        if update_request(@request, target_status)
          trigger_webhook_if_done(old_status, target_status)
          @request
        else
          false
        end
      end

      private

      def trigger_webhook_if_done(old_status, new_status)
        return unless @trigger_webhook
        return if old_status == new_status

        is_done = (kind == "housekeeping" && new_status == "completed") ||
                  (kind == "complaint" && new_status == "resolved") ||
                  (kind == "checkout" && new_status == "completed")

        return unless is_done

        event_type = "#{kind}_#{new_status}"
        payload = {
          request_id: @request.id,
          external_id: request_external_id,
          kind: kind,
          status: new_status,
          completed_at: request_completed_at,
          booking_id: @request.booking_id,
          confirmation_token: @request.booking&.confirmation_token,
          guest_name: @request.booking&.guest_name,
          guest_phone: @request.booking&.guest_phone,
          hotel_name: @request.booking&.hotel&.name || @request.hotel&.name
        }

        WebhookBroadcastJob.perform_later(event_type, payload)
      end

      def request_external_id
        return @request.external_id if @request.respond_to?(:external_id)

        @request.metadata.to_h["external_id"]
      end

      def request_completed_at
        return @request.completed_at if @request.respond_to?(:completed_at)

        @request.updated_at
      end

      def find_request
        case kind
        when "housekeeping"
          record = HousekeepingRequest.includes(:booking).find(request_id)
        when "complaint"
          record = ComplaintRequest.includes(:booking).find(request_id)
        when "checkout"
          record = CheckOutRequest.includes(:booking).find(request_id)
        else
          raise ActiveRecord::RecordNotFound
        end

        record_hotel_id = record.respond_to?(:hotel_id) ? record.hotel_id : nil
        record_hotel_id ||= record.booking&.hotel_id
        raise ActiveRecord::RecordNotFound unless record_hotel_id == hotel.id
        record
      end

      def normalize_status
        return "resolved" if kind == "complaint" && status == "completed"
        return "completed" if kind == "housekeeping" && status == "completed"
        return status if kind == "checkout" && status.in?(%w[new assigned in_progress completed no_task cancelled])
        return "new" if kind == "checkout" && status == "pending"
        return "assigned" if kind == "checkout" && status == "acknowledged"

        status
      end

      def update_request(record, target_status)
        case kind
        when "housekeeping"
          return false unless HousekeepingRequest::STATUSES.include?(target_status)

          completed_at = target_status == "completed" ? (record.completed_at || Time.current) : nil
          metadata = record.metadata.to_h
          if target_status.in?(%w[new no_task])
            if metadata["assigned_to"].present?
              history = Array(metadata["assignment_history"])
              history << {
                "assigned_to_name" => "Unassigned",
                "assigned_by_name" => "System",
                "timestamp" => Time.current.iso8601
              }
              metadata["assignment_history"] = history
            end
            metadata.delete("assigned_to")
            metadata.delete("assigned_to_name")
          end
          if record.update(status: target_status, completed_at: completed_at, metadata: metadata)
            mark_booking_rooms_cleaning(record) if target_status.in?(%w[new in_progress])
            mark_booking_rooms_ready(record) if target_status == "completed"
            true
          else
            false
          end
        when "complaint"
          return false unless ComplaintRequest::STATUSES.include?(target_status)

          completed_at = target_status == "resolved" ? (record.completed_at || Time.current) : nil
          record.update(status: target_status, completed_at: completed_at)
        when "checkout"
          return false unless CheckOutRequest::STATUSES.include?(target_status)

          metadata = record.metadata.to_h
          metadata["workflow_status"] = @status
          if @status == "no_task"
            metadata.delete("assigned_to")
            metadata.delete("assigned_to_name")
          end

          attrs = { status: target_status, metadata: metadata }
          attrs[:acknowledged_at] =
            case target_status
            when "assigned", "in_progress"
              record.acknowledged_at || Time.current
            when "completed"
              record.acknowledged_at
            else
              nil
            end
          if target_status == "no_task"
            attrs[:status] = "no_task"
          end

          updated = record.update(attrs)
          if updated
            mark_checkout_room_cleaning(record) if target_status == "in_progress"
            mark_checkout_room_ready(record) if target_status == "completed"
          end
          updated
        else
          false
        end
      end

      def mark_checkout_room_cleaning(record)
        room = checkout_room(record)
        return unless room

        room_status = RoomStatus.find_or_create_by!(hotel: record.booking.hotel, room_type: room.room_type, room_number: room.room_number)
        set_checkout_room_status(
          room_status: room_status,
          status: "cleaning",
          booking: record.booking,
          event_type: "checkout_room_cleaning_started",
          reason: record.guest_notes.presence || "Checkout Room Cleaning",
          metadata: { "checkout_request_id" => record.id }
        )
      end

      def mark_checkout_room_ready(record)
        room = checkout_room(record)
        return unless room

        active_housekeeping = HousekeepingRequest.where(booking_id: record.booking_id, room_number: room.room_number)
                                                 .where(status: %w[new assigned in_progress])
                                                 .exists?
        active_checkout = CheckOutRequest.where(booking_id: record.booking_id)
                                         .open_tasks
                                         .where.not(id: record.id)
                                         .includes(booking: :booking_rooms)
                                         .any? { |request| checkout_room(request)&.room_number.to_s == room.room_number.to_s }
        return if active_housekeeping || active_checkout

        room_status = RoomStatus.find_or_create_by!(hotel: record.booking.hotel, room_type: room.room_type, room_number: room.room_number)
        set_checkout_room_status(
          room_status: room_status,
          status: "ready",
          booking: record.booking,
          event_type: "checkout_room_cleaning_completed",
          reason: record.guest_notes.presence || "Checkout Room Cleaning",
          metadata: { "checkout_request_id" => record.id }
        )
      end

      def set_checkout_room_status(room_status:, status:, booking:, event_type:, reason:, metadata:)
        result = Rooms::SetStatus.new(
          room_status: room_status,
          status: status,
          user: nil,
          booking: booking,
          event_type: event_type,
          reason: reason,
          metadata: metadata
        ).call
        return if result.success?

        # Legacy room states must not prevent checkout cleaning from updating
        # the operational status shown on the housekeeping board.
        room_status.update!(status: status, last_changed_at: Time.current, notes: reason)
      end

      def checkout_room(record)
        room_number = record.metadata.to_h["room_number"].presence
        rooms = record.booking.booking_rooms.includes(:room_type)
        rooms = rooms.where(room_number: room_number) if room_number.present?
        rooms.where.not(room_number: [ nil, "" ]).first
      end

      def mark_booking_rooms_cleaning(record)
        if record.room_number.present?
          r_status = RoomStatus.find_or_create_by!(
            hotel: record.hotel || record.booking&.hotel,
            room_type: record.room_type || record.booking&.booking_rooms&.first&.room_type,
            room_number: record.room_number
          )

          Rooms::SetStatus.new(
            room_status: r_status,
            status: "cleaning",
            user: nil,
            booking: record.booking,
            event_type: "housekeeping_request_dispatched",
            reason: record.request_details,
            metadata: { "housekeeping_request_id" => record.id }
          ).call
        end

        return unless record.booking

        record.booking.booking_rooms.includes(:room_type).where.not(room_number: [ nil, "" ]).find_each do |booking_room|
          next if booking_room.room_number == record.room_number

          room_status = RoomStatus.find_or_create_by!(
            hotel: record.booking.hotel,
            room_type: booking_room.room_type,
            room_number: booking_room.room_number
          )

          Rooms::SetStatus.new(
            room_status: room_status,
            status: "cleaning",
            user: nil,
            booking: record.booking,
            event_type: "housekeeping_request_dispatched",
            reason: record.request_details,
            metadata: { "housekeeping_request_id" => record.id }
          ).call
        end
      end

      def mark_booking_rooms_ready(record)
        hotel_id = record.hotel_id || record.booking&.hotel_id
        reason_text = record.request_details.presence || "Housekeeping completed"

        if record.room_number.present?
          has_active = HousekeepingRequest.left_joins(booking: :booking_rooms)
                                          .where("housekeeping_requests.hotel_id = :hotel_id OR bookings.hotel_id = :hotel_id", hotel_id: hotel_id)
                                          .where(
                                            "housekeeping_requests.room_number = :room_number OR (housekeeping_requests.room_number IS NULL AND booking_rooms.room_number = :room_number)",
                                            room_number: record.room_number
                                          )
                                          .where(status: %w[new assigned in_progress])
                                          .where.not(id: record.id)
                                          .exists?

          unless has_active
            r_status = RoomStatus.find_or_create_by!(
              hotel: record.hotel || record.booking&.hotel,
              room_type: record.room_type || record.booking&.booking_rooms&.first&.room_type,
              room_number: record.room_number
            )

            Rooms::SetStatus.new(
              room_status: r_status,
              status: "ready",
              user: nil,
              booking: record.booking,
              event_type: "room_status_changed",
              reason: reason_text,
              metadata: { "housekeeping_request_id" => record.id }
            ).call
          end
        end

        return unless record.booking

        record.booking.booking_rooms.includes(:room_type).where.not(room_number: [ nil, "" ]).find_each do |booking_room|
          next if booking_room.room_number == record.room_number

          has_active = HousekeepingRequest.left_joins(booking: :booking_rooms)
                                          .where("housekeeping_requests.hotel_id = :hotel_id OR bookings.hotel_id = :hotel_id", hotel_id: hotel_id)
                                          .where(
                                            "housekeeping_requests.room_number = :room_number OR (housekeeping_requests.room_number IS NULL AND booking_rooms.room_number = :room_number)",
                                            room_number: booking_room.room_number
                                          )
                                          .where(status: %w[new assigned in_progress])
                                          .where.not(id: record.id)
                                          .exists?

          unless has_active
            room_status = RoomStatus.find_or_create_by!(
              hotel: record.booking.hotel,
              room_type: booking_room.room_type,
              room_number: booking_room.room_number
            )

            Rooms::SetStatus.new(
              room_status: room_status,
              status: "ready",
              user: nil,
              booking: record.booking,
              event_type: "room_status_changed",
              reason: reason_text,
              metadata: { "housekeeping_request_id" => record.id }
            ).call
          end
        end
      end
    end
  end
end
