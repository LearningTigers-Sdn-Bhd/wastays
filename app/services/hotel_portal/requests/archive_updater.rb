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
        if kind == "checkout"
          metadata = request.metadata.to_h
          metadata["archived_at"] = Time.current.iso8601
          request.update(metadata: metadata) ? request : false
        else
          request.archive!
          request.save ? request : false
        end
      end

      def unarchive
        request = find_request
        if kind == "checkout"
          metadata = request.metadata.to_h
          metadata.delete("archived_at")
          request.update(metadata: metadata) ? request : false
        else
          request.unarchive!
          if request.respond_to?(:status=) && request.status.to_s == "cancelled"
          request.status = "pending"
          request.completed_at = nil if request.respond_to?(:completed_at=)
          request.internal_notes = [] if request.respond_to?(:internal_notes=)
          end
          request.save ? request : false
        end
      end

      private

      def find_request
        Finder.new(hotel: hotel, kind: kind, request_id: request_id).call
      end
    end
  end
end
