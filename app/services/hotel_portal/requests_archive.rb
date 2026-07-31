# frozen_string_literal: true

module HotelPortal
  class RequestsArchive
    include Requests::Narrowing
    include Requests::Paging

    attr_reader :hotel, :params

    def initialize(hotel, params = {})
      @hotel = hotel
      @params = params || {}
    end

    # The archive is read by when a request was put away, which is the only date
    # a row here has that a reader is looking for.
    def date_window
      @date_window ||= Requests::DateWindow.new(
        hotel: hotel,
        anchor_date: params[:date],
        days: params[:days]
      )
    end

    # A kind the filter bar ruled out is a query not worth making, so its source
    # is left out rather than narrowed down to nothing.
    #
    # Public because this is the whole of what the archive is: the board's
    # Archived lane reads these the way it reads its own sources. The archive
    # had a page of its own once, and this outlived it.
    def sources
      @sources ||= [
        (housekeeping_source if wanted_kind?("housekeeping")),
        (complaint_source if wanted_kind?("complaint")),
        (checkout_source if wanted_kind?("checkout"))
      ].compact
    end

    private

    # The archive is only ever the archived, so only the archived is asked for.
    # A request reaches its booking rather than the other way around, which keeps
    # a hotel's whole history of requests out of a page showing a page of them.
    #
    # None of these carry an order of their own: the page applies the one the
    # cursor understands, and an order set here would sort ahead of it.
    def housekeeping_source
      Source.new(
        name: "housekeeping",
        relation: narrow(HousekeepingRequest.in_hotel(hotel).archived, kind: "housekeeping")
          .where.not(booking_id: nil)
          .where(archived_at: window_range)
          .includes(:booking),
        sort_column: :archived_at,
        builder: ->(request) { row_for(kind: "housekeeping", request: request, title: request.request_details) }
      )
    end

    def complaint_source
      Source.new(
        name: "complaint",
        relation: narrow(ComplaintRequest.where(booking_id: hotel_booking_ids).archived, kind: "complaint")
          .where(archived_at: window_range)
          .includes(:booking),
        sort_column: :archived_at,
        builder: ->(request) { row_for(kind: "complaint", request: request, title: request.complaint_details) }
      )
    end

    # A checkout carries no archived_at column: cancelling is an ending of its
    # own, and completing is archived by a note in its metadata. Neither is a
    # column the window can be read against or the page ordered by, so when the
    # record was last written stands in for when it was put away -- which is what
    # putting it away did.
    def checkout_source
      Source.new(
        name: "checkout",
        relation: narrow(CheckOutRequest.where(booking_id: hotel_booking_ids), kind: "checkout")
          .where(
            "check_out_requests.status = 'cancelled' OR " \
            "(check_out_requests.status = 'completed' AND COALESCE(check_out_requests.metadata->>'archived_at', '') <> '')"
          )
          .where(updated_at: window_range)
          .includes(:booking),
        sort_column: :updated_at,
        builder: ->(request) { checkout_row(request) }
      )
    end

    def hotel_booking_ids
      @hotel_booking_ids ||= hotel.bookings.select(:id)
    end

    def window_range
      @window_range ||= date_window.range
    end

    def wanted_kind?(kind)
      wanted = params[:kind].to_s
      wanted.blank? || wanted == "all" || wanted == kind
    end

    # -- Rows -----------------------------------------------------------------
    #
    # `sort_at` is the value of the source's sort column and nothing else. The
    # cursor names the last row by it, so a row that reports one time and is
    # ordered by another puts the page boundary in a place the next query cannot
    # find.

    def row_for(kind:, request:, title:)
      booking = request.booking

      Requests::Card.new(
        kind: kind,
        record_kind: kind,
        request_id: request.id,
        booking_id: booking.id,
        booking_token: booking.confirmation_token,
        guest_name: booking.guest_name,
        title: title,
        requested_at: request.display_requested_at,
        completed_at: request.completed_at,
        status: request.status,
        internal_notes: request.internal_notes_list,
        archived_at: request.archived_at,
        sort_at: request.archived_at
      )
    end

    def checkout_row(request)
      booking = request.booking

      Requests::Card.new(
        kind: "checkout",
        record_kind: "checkout",
        request_id: request.id,
        booking_id: booking.id,
        booking_token: booking.confirmation_token,
        guest_name: booking.guest_name,
        title: request.guest_notes.presence || "Checkout requested",
        requested_at: request.requested_at,
        completed_at: request.completed_at,
        status: request.status,
        internal_notes: [],
        # What the note says it was, for a reader; the row is still ordered by the
        # column the query could reach.
        archived_at: request.metadata.to_h["archived_at"].presence || request.updated_at,
        sort_at: request.updated_at
      )
    end

    # The archive is where notes are read, so it is where they are searched.
    def search_internal_notes?
      true
    end
  end
end
