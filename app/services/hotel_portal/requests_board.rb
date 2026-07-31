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
      when :checkout then [ open_checkout_source, cleaning_source ]
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
        # A checkout's room cleaning belongs in the checkout column, whether or
        # not the checkout it stands for is there to hold it.
        relation: narrow(open_housekeeping_scope, kind: "housekeeping")
          .where(status: HOUSEKEEPING_OPEN_STATUSES)
          .where.not(id: cleaning_ids)
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

    # The cleanings no checkout on the board already stands for. One that names a
    # checkout that is here would be the same job said twice; one whose checkout
    # is not here keeps its place, because losing the work is worse.
    def cleaning_source
      Source.new(
        name: "cleaning",
        relation: narrow(open_housekeeping_scope, kind: "housekeeping")
          .where(status: HOUSEKEEPING_OPEN_STATUSES)
          .where(id: uncovered_cleaning_ids)
          .includes(booking: :booking_rooms),
        sort_column: :requested_at,
        builder: ->(request) { housekeeping_card(request, bucket: :checkout, kind: "checkout") }
      )
    end

    def completed_housekeeping_source
      Source.new(
        name: "housekeeping",
        relation: narrow(open_housekeeping_scope, kind: "housekeeping")
          .where(status: "completed")
          .where(completed_at: window_range)
          .where.not(id: covered_cleaning_ids)
          .includes(booking: :booking_rooms),
        sort_column: :completed_at,
        builder: ->(request) {
          housekeeping_card(request, bucket: :completed, kind: request.checkout_cleaning? ? "checkout" : "housekeeping")
        }
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

    def open_housekeeping_scope
      HousekeepingRequest
        .in_hotel(hotel)
        .active
        # Every card names a guest, so a task raised against a room and no
        # booking has never belonged on this board.
        .where.not(booking_id: nil)
    end

    def open_complaint_scope
      ComplaintRequest.where(booking_id: hotel_booking_ids).active
    end

    def open_checkout_scope
      CheckOutRequest.where(booking_id: hotel_booking_ids).open_tasks
    end

    def hotel_booking_ids
      @hotel_booking_ids ||= hotel.bookings.select(:id)
    end

    def window_range
      @window_range ||= date_window.range
    end

    # -- Telling one job from two ---------------------------------------------
    #
    # Read once for the whole board rather than per page: whether a checkout is
    # on the board is not a fact about a page, and a cleaning must not appear or
    # disappear depending on how far somebody has scrolled. Read unnarrowed for
    # the same reason -- a search that hides a checkout must not surface the
    # cleaning standing for it.
    #
    # "On the board" is what each lane's own scope is: open work is unbounded and
    # finished work is inside the window. Asking the window of both halves, as
    # this did when the window bounded every lane, would leave an old open
    # checkout off this list while its lane still showed it -- and the cleaning
    # standing for it would then be drawn twice.

    def checkout_rows_on_board
      @checkout_rows_on_board ||= begin
        base = CheckOutRequest.where(booking_id: hotel_booking_ids)
        open_rows = base.open_tasks.pluck(:id, :booking_id)
        finished_rows = base.where(status: "completed")
                            .where(completed_at: window_range)
                            .where("COALESCE(check_out_requests.metadata->>'archived_at', '') = ''")
                            .pluck(:id, :booking_id)
        open_rows + finished_rows
      end
    end

    def checkout_ids_on_board
      @checkout_ids_on_board ||= checkout_rows_on_board.map(&:first).to_set
    end

    def checkout_booking_ids_on_board
      @checkout_booking_ids_on_board ||= checkout_rows_on_board.map(&:last).to_set
    end

    # Records the housekeeping tasks backfill made say they are a cleaning
    # through checkout_request_id; older ones only say so by their details.
    CLEANING_CONDITION = <<~SQL.squish
      COALESCE(housekeeping_requests.metadata->>'checkout_request_id', '') <> ''
        OR TRIM(housekeeping_requests.request_details) = 'Checkout Room Cleaning'
    SQL

    def cleaning_rows
      @cleaning_rows ||= open_housekeeping_scope
        .where(CLEANING_CONDITION)
        .where(
          "housekeeping_requests.status IN (:open) OR " \
          "(housekeeping_requests.completed_at >= :from AND housekeeping_requests.completed_at < :to)",
          open: HOUSEKEEPING_OPEN_STATUSES, from: window_range.begin, to: window_range.end
        )
        .pluck(:id, :booking_id, Arel.sql("housekeeping_requests.metadata->>'checkout_request_id'"))
    end

    def cleaning_ids
      @cleaning_ids ||= cleaning_rows.map(&:first)
    end

    def covered_cleaning_ids
      @covered_cleaning_ids ||= cleaning_rows.filter_map do |id, booking_id, linked_checkout_id|
        covered = if linked_checkout_id.present?
          checkout_ids_on_board.include?(linked_checkout_id.to_i)
        else
          checkout_booking_ids_on_board.include?(booking_id)
        end

        id if covered
      end
    end

    def uncovered_cleaning_ids
      @uncovered_cleaning_ids ||= cleaning_ids - covered_cleaning_ids
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
        status: request.metadata&.dig("workflow_status").presence || HousekeepingTasks.checkout_workflow_status_for(request.status),
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
  end
end
