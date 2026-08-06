# frozen_string_literal: true

module HotelPortal
  class RequestsBoard
    include Requests::Narrowing
    include Requests::Paging

    # The lanes, in the order they are shown. Declared by Column so the board and
    # the board's header cannot come to disagree about either.
    COLUMNS = Requests::Column.keys

    # The statuses that still owe work, per kind. Subtracted from the full list
    # so that a status added to a model has to be excluded here deliberately
    # rather than quietly dropping off the board.
    HOUSEKEEPING_OPEN_STATUSES = (HousekeepingRequest::STATUSES - %w[completed cancelled no_task]).freeze
    COMPLAINT_OPEN_STATUSES = (ComplaintRequest::STATUSES - %w[resolved cancelled]).freeze

    attr_reader :hotel, :params

    def initialize(hotel, params = {})
      @hotel = hotel
      @params = params || {}
    end

    # The stretch of time every column is read through. Outstanding work is
    # placed by when it was asked for and finished work by when it was finished,
    # so a request raised before the window and finished inside it is still
    # something that happened in the window.
    def date_window
      @date_window ||= Requests::DateWindow.new(
        hotel: hotel,
        anchor_date: params[:date],
        days: params[:days]
      )
    end

    # One column, from the cursor onwards.
    def page(column, cursor: nil, limit: PAGE_SIZE)
      paged(sources_for(column), cursor: cursor, limit: limit)
    end

    # The lanes on screen. A lane switched off is not paged at all, which is
    # where the board's cost actually sits -- reading the lanes is most of what a
    # render spends, and a hidden lane spends none of it.
    #
    # Counts are still asked for every lane, because the toolbar names them all
    # with how much is in each: that is the control the lanes are switched on
    # *with*, so it cannot only describe the ones already showing.
    #
    # Nothing switched on means all of them. An empty selection arrives as no
    # parameter at all -- the form drops empty inputs on a GET -- so a board
    # showing nothing would be indistinguishable from a board just opened, and
    # the emptier of the two readings is the one nobody wants.
    def visible_columns
      @visible_columns ||= begin
        wanted = Array(params[:lanes]).map(&:to_s)
        if wanted.empty? || wanted.include?("all")
          COLUMNS
        else
          chosen = COLUMNS.select { |column| wanted.include?(column.to_s) }
          chosen.presence || COLUMNS
        end
      end
    end

    def pages
      @pages ||= visible_columns.index_with { |column| page(column) }
    end

    def board_columns
      @board_columns ||= pages.transform_values(&:cards)
    end

    # Where each column got to, so the view can ask for the rest of it.
    def next_cursors
      @next_cursors ||= pages.transform_values(&:next_cursor)
    end

    # The whole column, not the page of it on screen. Asked of the database,
    # because the page no longer knows how long the column is.
    def board_counts
      @board_counts ||= COLUMNS.index_with { |column| sources_for(column).sum { |source| source.relation.count } }
    end

    private

    # -- What each column is drawn from --------------------------------------

    def sources_for(column)
      case column.to_sym
      when :housekeeping then [ housekeeping_source ]
      when :complaint then [ complaint_source ]
      when :checkout then [ open_checkout_source ]
      when :completed then [ completed_housekeeping_source, resolved_complaint_source, completed_checkout_source ]
      when :archived then archive.sources
      else []
      end
    end

    # What has been put away, read as a column rather than as a page of its own.
    # It answers to the same filters and the same window as everything else here
    # -- against archived_at, which is the date a row in the archive has.
    def archive
      @archive ||= RequestsArchive.new(hotel, params)
    end

    def housekeeping_source
      Source.new(
        name: "housekeeping",
        relation: narrow(housekeeping_scope, kind: "housekeeping")
          .where(status: HOUSEKEEPING_OPEN_STATUSES)
          .includes(booking: :booking_rooms),
        sort_column: :requested_at,
        builder: ->(request) { housekeeping_card(request, bucket: :housekeeping, kind: "housekeeping") }
      )
    end

    def complaint_source
      Source.new(
        name: "complaint",
        relation: narrow(open_complaint_scope, kind: "complaint")
          .where(status: COMPLAINT_OPEN_STATUSES)
          .includes(booking: :booking_rooms),
        sort_column: :requested_at,
        builder: ->(request) { complaint_card(request, bucket: :complaint) }
      )
    end

    def open_checkout_source
      Source.new(
        name: "checkout",
        relation: narrow(open_checkout_scope, kind: "checkout")
          .includes(booking: :booking_rooms),
        sort_column: :requested_at,
        builder: ->(request) { open_checkout_card(request) }
      )
    end

    def completed_housekeeping_source
      Source.new(
        name: "housekeeping",
        relation: narrow(housekeeping_scope, kind: "housekeeping")
          .where(status: "completed")
          .where(completed_at: window_range)
          .includes(booking: :booking_rooms),
        sort_column: :completed_at,
        builder: ->(request) { housekeeping_card(request, bucket: :completed, kind: "housekeeping") }
      )
    end

    def resolved_complaint_source
      Source.new(
        name: "complaint",
        relation: narrow(open_complaint_scope, kind: "complaint")
          .where(status: "resolved")
          .where(completed_at: window_range)
          .includes(booking: :booking_rooms),
        sort_column: :completed_at,
        builder: ->(request) { complaint_card(request, bucket: :completed) }
      )
    end

    def completed_checkout_source
      Source.new(
        name: "checkout",
        relation: narrow(CheckOutRequest.where(booking_id: hotel_booking_ids), kind: "checkout")
          .where(status: "completed")
          .where(completed_at: window_range)
          .where("COALESCE(check_out_requests.metadata->>'archived_at', '') = ''")
          .includes(booking: :booking_rooms),
        sort_column: :completed_at,
        builder: ->(request) { completed_checkout_card(request) }
      )
    end

    # -- The work each column is drawn from ------------------------------------

    def housekeeping_scope
      HousekeepingRequest
        .in_hotel(hotel)
        .active
        .guest_requests
        .where.not(booking_id: nil)
    end

    def open_complaint_scope
      ComplaintRequest.where(booking_id: hotel_booking_ids).active
    end

    def open_checkout_scope
      CheckOutRequest.joins(:booking).where(booking_id: hotel_booking_ids)
                     .where(bookings: { status: ::Bookings::Occupancy::OCCUPIED_STATUSES })
                     .open_tasks
    end

    def hotel_booking_ids
      @hotel_booking_ids ||= hotel.bookings.select(:id)
    end

    def window_range
      @window_range ||= date_window.range
    end

    # -- Cards ----------------------------------------------------------------

    def housekeeping_card(request, bucket:, kind:)
      base_card(request, bucket: bucket, kind: kind, record_kind: "housekeeping",
                title: request.request_details).tap do |card|
        card.room_number = request.room_number.presence || request.booking&.booking_rooms&.first&.room_number
      end
    end

    def complaint_card(request, bucket:)
      base_card(request, bucket: bucket, kind: "complaint", record_kind: "complaint",
                title: request.complaint_details).tap do |card|
        card.room_number = request.booking&.booking_rooms&.first&.room_number
      end
    end

    def base_card(request, bucket:, kind:, record_kind:, title:)
      booking = request.booking

      Requests::Card.new(
        kind: kind,
        record_kind: record_kind,
        request_id: request.id,
        booking_id: booking.id,
        booking_token: booking.confirmation_token,
        guest_name: booking.guest_name,
        title: title,
        requested_at: request.display_requested_at,
        status: request.status,
        completed_at: request.completed_at,
        source: request.metadata&.dig("source"),
        internal_notes: request.internal_notes_list,
        # Outstanding work is placed by when it was asked for and finished work by
        # when it was finished, so the column's sort column is the one reported.
        sort_at: bucket == :completed ? request.completed_at : request.display_requested_at
      )
    end

    def open_checkout_card(request)
      booking = request.booking

      Requests::Card.new(
        kind: "checkout",
        record_kind: "checkout",
        request_id: request.id,
        booking_id: booking.id,
        booking_token: booking.confirmation_token,
        guest_name: booking.guest_name,
        room_number: request.metadata&.dig("room_number").presence || booking.booking_rooms.first&.room_number,
        title: request.guest_notes.presence || "Checkout requested",
        requested_at: request.requested_at,
        status: checkout_display_status(request),
        sort_at: request.requested_at
      )
    end

    def completed_checkout_card(request)
      booking = request.booking

      Requests::Card.new(
        kind: "checkout",
        record_kind: "checkout",
        request_id: request.id,
        booking_id: booking.id,
        booking_token: booking.confirmation_token,
        guest_name: booking.guest_name,
        room_number: request.metadata&.dig("room_number").presence || booking.booking_rooms.first&.room_number,
        title: request.guest_notes.presence || "Checkout requested",
        requested_at: request.requested_at,
        status: request.status,
        completed_at: request.completed_at,
        internal_notes: [],
        sort_at: request.completed_at
      )
    end

    # A checkout carries legacy statuses of its own; read one in the words the
    # board works in.
    def checkout_display_status(request)
      case request.status
      when "pending" then "new"
      when "acknowledged" then "assigned"
      else request.status
      end
    end
  end
end
