# frozen_string_literal: true

module HotelPortal
  module Requests
    # One request as the detail sheet reads it.
    #
    # The sheet serves the board and the archive from the same record, and the
    # three tables behind a request answer the same questions differently: a
    # checkout keeps no internal notes and no archived_at column, and only a
    # housekeeping request carries a room number of its own.
    # Answering that here is what lets one sheet replace the two dialogs that
    # described the same request in different words.
    class DetailPresenter
      KIND_LABELS = {
        "housekeeping" => "Housekeeping",
        "complaint" => "Complaint",
        "checkout" => "Checkout"
      }.freeze

      attr_reader :request, :kind

      def initialize(request:, kind:, hotel:)
        @request = request
        @kind = kind.to_s
        @hotel = hotel
      end

      def kind_label
        KIND_LABELS.fetch(kind, kind.titleize)
      end

      def booking
        request.booking
      end

      def booking_token
        booking&.confirmation_token
      end

      def guest_name
        booking&.guest_name
      end

      def title
        case kind
        when "complaint" then request.complaint_details
        when "checkout" then request.guest_notes.presence || "Checkout requested"
        else request.request_details
        end
      end

      def status
        request.status
      end

      def room_number
        own = request.room_number if request.respond_to?(:room_number)
        own.presence || request.metadata.to_h["room_number"].presence || booking&.booking_rooms&.first&.room_number
      end

      def requested_at
        request.respond_to?(:display_requested_at) ? request.display_requested_at : request.requested_at
      end

      def completed_at
        request.completed_at
      end

      def archived_at
        return request.archived_at if request.respond_to?(:archived_at)

        parse_time(request.metadata.to_h["archived_at"])
      end

      def archived?
        archived_at.present?
      end

      def internal_notes
        request.respond_to?(:internal_notes_list) ? request.internal_notes_list : []
      end

      def internal_notes?
        internal_notes.any?
      end

      # Where the request came from. A guest raising one on the concierge page is
      # worth telling apart from a dispatcher raising one at the desk.
      def source
        request.metadata.to_h["source"]
      end

      def guest_raised?
        source.to_s == "concierge_page"
      end

      def source_label
        guest_raised? ? "Guest, via concierge page" : "Front desk"
      end

      def assigned_to_name
        request.metadata.to_h["assigned_to_name"].presence
      end

      def booking_id
        request.booking_id
      end

      private

      def parse_time(value)
        return if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
