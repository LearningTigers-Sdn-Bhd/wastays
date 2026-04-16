module HotelPortal
  module Requests
    class ArchiveUpdater
      attr_reader :hotel, :kind, :request_id

      def initialize(hotel:, kind:, request_id:)
        @hotel = hotel
        @kind = kind.to_s
        @request_id = request_id
      end

      def archive
        request = find_request
        request.archive!
        request.save ? request : false
      end

      def unarchive
        request = find_request
        request.unarchive!
        if request.respond_to?(:status=) && request.status.to_s == "cancelled"
          request.status = "pending"
          request.completed_at = nil if request.respond_to?(:completed_at=)
          request.internal_notes = [] if request.respond_to?(:internal_notes=)
        end
        request.save ? request : false
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
    end
  end
end
