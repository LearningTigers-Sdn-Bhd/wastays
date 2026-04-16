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

        if update_request(@request, target_status)
          @request
        else
          false
        end
      end

      private

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
