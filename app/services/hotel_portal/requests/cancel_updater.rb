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

      # Cancelling records why on the request itself, so it reaches only the two
      # kinds that keep internal notes. A checkout is released through the
      # housekeeping board instead.
      CANCELLABLE_KINDS = %w[housekeeping complaint].freeze

      def find_request
        Finder.new(hotel: hotel, kind: kind, request_id: request_id, kinds: CANCELLABLE_KINDS).call
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
