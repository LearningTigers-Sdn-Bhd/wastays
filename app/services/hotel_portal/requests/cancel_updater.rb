module HotelPortal
  module Requests
    class CancelUpdater
      attr_reader :hotel, :kind, :request_id, :note, :request

      def initialize(hotel:, kind:, request_id:, note:)
        @hotel = hotel
        @kind = kind.to_s
        @request_id = request_id
        @note = note.to_s
      end

      def call
        @request = find_request
        return false if note.blank?

        if cancel_request(@request)
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

      def cancel_request(record)
        record.add_internal_note(note)
        record.status = "cancelled"
        record.completed_at = nil if record.respond_to?(:completed_at=)
        record.archive!
        record.save
      end
    end
  end
end
