module HotelPortal
  module Requests
    class StatusUpdater
      attr_reader :hotel, :kind, :request_id, :status, :request

      def initialize(hotel:, kind:, request_id:, status:)
        @hotel = hotel
        @kind = kind.to_s
        @request_id = request_id
        @status = status.to_s
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
        return if old_status == new_status

        is_done = (kind == "housekeeping" && new_status == "completed") ||
                  (kind == "complaint" && new_status == "resolved")

        return unless is_done

        event_type = "#{kind}_#{new_status}"
        payload = {
          request_id: @request.id,
          external_id: @request.external_id,
          kind: kind,
          status: new_status,
          completed_at: @request.completed_at,
          booking_id: @request.booking_id,
          confirmation_token: @request.booking.confirmation_token,
          guest_name: @request.booking.guest_name,
          guest_phone: @request.booking.guest_phone,
          hotel_name: @request.booking.hotel.name
        }

        WebhookBroadcastJob.perform_later(event_type, payload)
      end

      def find_request
        case kind
        when "housekeeping"
          record = HousekeepingRequest.includes(:booking).find(request_id)
        when "complaint"
          record = ComplaintRequest.includes(:booking).find(request_id)
        else
          raise ActiveRecord::RecordNotFound
        end

        raise ActiveRecord::RecordNotFound unless record.booking.hotel_id == hotel.id
        record
      end

      def normalize_status
        return "resolved" if kind == "complaint" && status == "completed"
        return "completed" if kind == "housekeeping" && status == "completed"

        status
      end

      def update_request(record, target_status)
        case kind
        when "housekeeping"
          return false unless HousekeepingRequest::STATUSES.include?(target_status)

          completed_at = target_status == "completed" ? (record.completed_at || Time.current) : nil
          record.update(status: target_status, completed_at: completed_at)
        when "complaint"
          return false unless ComplaintRequest::STATUSES.include?(target_status)

          completed_at = target_status == "resolved" ? (record.completed_at || Time.current) : nil
          record.update(status: target_status, completed_at: completed_at)
        else
          false
        end
      end
    end
  end
end
