# frozen_string_literal: true

module HotelPortal
  class RequestsBoard
    include Rails.application.routes.url_helpers

    # How long a finished request stays worth looking at. Anything older belongs
    # to the archive, so the board never loads it: what the board costs follows
    # how busy the hotel is now rather than how long it has been open.
    RECENTLY_COMPLETED_WINDOW = 7.days

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

    def board_columns
      @board_columns ||= begin
        cards = filtered_request_cards

        {
          housekeeping: cards.select { |card| card[:bucket] == :housekeeping },
          complaint: cards.select { |card| card[:bucket] == :complaint },
          completed: (cards.select { |card| card[:bucket] == :completed } + checkout_completed_request_cards)
                          .sort_by { |card| card[:completed_at] || Time.zone.at(0) }
                          .reverse,
          checkout: checkout_request_cards + cards.select { |card| card[:bucket] == :checkout }
        }
      end
    end

    def board_counts
      board_columns.transform_values(&:count)
    end

    private

    # Every checkout already standing on the board, open or just completed.
    # A housekeeping request for the same cleaning is the same job said twice,
    # and the checkout is the one that carries the workflow.
    def checkout_cards
      @checkout_cards ||= checkout_request_cards + checkout_completed_request_cards
    end

    def checkout_card_request_ids
      @checkout_card_request_ids ||= checkout_cards.map { |card| card[:request_id] }.to_set
    end

    def checkout_card_booking_ids
      @checkout_card_booking_ids ||= checkout_cards.map { |card| card[:booking_id] }.to_set
    end

    # A cleaning that names its checkout is redundant when that checkout is on
    # the board. One that only says so by its details has no id to match, so
    # the booking is as close as it can be placed -- and a booking with no
    # checkout card keeps its cleaning rather than losing the work.
    def covered_by_checkout_card?(request, booking)
      linked_id = request.checkout_request_id
      return checkout_card_request_ids.include?(linked_id.to_i) if linked_id.present?

      checkout_card_booking_ids.include?(booking.id)
    end

    def checkout_request_cards
      @checkout_request_cards ||= open_checkout_requests.map do |request|
        booking = request.booking

        {
          kind: "checkout",
          bucket: :checkout,
          request_id: request.id,
          booking_id: booking.id,
          booking_token: booking.confirmation_token,
          guest_name: booking.guest_name,
          room_number: request.metadata&.dig("room_number").presence || booking.booking_rooms.first&.room_number,
          title: request.guest_notes.presence || "Checkout requested",
          requested_at: request.requested_at,
          status: request.metadata&.dig("workflow_status").presence || HousekeepingTasks.checkout_workflow_status_for(request.status),
          complete_url: hotel_complete_checkout_request_path(hotel, request.id),
          booking_url: hotel_booking_workspace_path(hotel, booking, tab: "housekeeping_requests")
        }
      end
    end

    def checkout_completed_request_cards
      @checkout_completed_request_cards ||= completed_checkout_requests.map do |request|
        booking = request.booking

        {
          kind: "checkout",
          bucket: :completed,
          request_id: request.id,
          booking_id: booking.id,
          booking_token: booking.confirmation_token,
          guest_name: booking.guest_name,
          room_number: request.metadata&.dig("room_number").presence || booking.booking_rooms.first&.room_number,
          title: request.guest_notes.presence || "Checkout requested",
          requested_at: request.requested_at,
          status: request.status,
          # A checkout has no completed_at of its own to read.
          completed_at: request.updated_at,
          internal_notes: [],
          archive_url: hotel_archive_request_path(hotel, kind: "checkout", request_id: request.id),
          booking_url: hotel_booking_path(hotel, booking)
        }
      end
    end

    # -- What the board asks the database for -------------------------------
    #
    # One query per kind, each narrowed to the hotel and to work the board
    # actually shows. Nothing walks the hotel's bookings: a request reaches its
    # booking, not the other way around, so a hotel's history stays out of it.

    def completed_since
      @completed_since ||= RECENTLY_COMPLETED_WINDOW.ago
    end

    def hotel_booking_ids
      @hotel_booking_ids ||= hotel.bookings.select(:id)
    end

    def housekeeping_requests
      @housekeeping_requests ||= HousekeepingRequest
        .in_hotel(hotel)
        .active
        # Every card names a guest, so a task raised against a room and no
        # booking has never belonged on this board.
        .where.not(booking_id: nil)
        .where(
          "housekeeping_requests.status IN (:open) OR " \
          "(housekeeping_requests.status = 'completed' AND housekeeping_requests.completed_at >= :since)",
          open: HOUSEKEEPING_OPEN_STATUSES, since: completed_since
        )
        .includes(booking: :booking_rooms)
        .order(requested_at: :desc)
        .to_a
    end

    def complaint_requests
      @complaint_requests ||= ComplaintRequest
        .where(booking_id: hotel_booking_ids)
        .active
        .where(
          "complaint_requests.status IN (:open) OR " \
          "(complaint_requests.status = 'resolved' AND complaint_requests.completed_at >= :since)",
          open: COMPLAINT_OPEN_STATUSES, since: completed_since
        )
        .includes(booking: :booking_rooms)
        .order(requested_at: :desc)
        .to_a
    end

    def open_checkout_requests
      @open_checkout_requests ||= CheckOutRequest
        .where(booking_id: hotel_booking_ids)
        .open_tasks
        .includes(booking: :booking_rooms)
        .order(requested_at: :desc)
        .to_a
    end

    # A checkout keeps no completed_at, so how recently it finished can only be
    # read from when it was last written.
    def completed_checkout_requests
      @completed_checkout_requests ||= CheckOutRequest
        .where(booking_id: hotel_booking_ids)
        .where(status: "completed")
        .where(updated_at: completed_since..)
        .where("COALESCE(check_out_requests.metadata->>'archived_at', '') = ''")
        .includes(booking: :booking_rooms)
        .order(updated_at: :desc)
        .to_a
    end

    def request_cards
      @request_cards ||= build_request_cards
    end

    def filtered_request_cards
      cards = request_cards
      cards = cards.select { |card| search_match?(card) }
      cards = cards.select { |card| status_match?(card) }
      cards = cards.select { |card| date_range_match?(card) }
      cards
    end

    def build_request_cards
      cards = []

      housekeeping_requests.each do |request|
        # Checkout room cleaning belongs in the checkout column rather than in
        # housekeeping -- unless the checkout it stands for is already there,
        # in which case showing it as well shows one job as two.
        checkout_cleaning = request.checkout_cleaning?
        next if checkout_cleaning && covered_by_checkout_card?(request, request.booking)

        card = build_card(
          kind: checkout_cleaning ? "checkout" : "housekeeping",
          request: request,
          booking: request.booking,
          title: request.request_details
        )
        cards << card if card[:bucket].present?
      end

      complaint_requests.each do |request|
        card = build_card(
          kind: "complaint",
          request: request,
          booking: request.booking,
          title: request.complaint_details
        )
        cards << card if card[:bucket].present?
      end

      cards.sort_by { |card| card[:requested_at] || Time.zone.at(0) }.reverse
    end

    def build_card(kind:, request:, booking:, title:)
      {
        kind: kind,
        bucket: request_bucket(kind, request),
        request_id: request.id,
        booking_id: booking.id,
        booking_token: booking.confirmation_token,
        guest_name: booking.guest_name,
        room_number: request.respond_to?(:room_number) ? request.room_number : booking.booking_rooms.first&.room_number,
        title: title,
        requested_at: request.display_requested_at,
        requested_at_raw: request.display_requested_at,
        status: request.status,
        completed_at: request.completed_at,
        source: request.metadata&.dig("source"),
        internal_notes: request.respond_to?(:internal_notes_list) ? request.internal_notes_list : [],
        archive_url: hotel_archive_request_path(hotel, kind: kind, request_id: request.id),
        update_url: hotel_request_status_path(hotel, kind: kind, request_id: request.id),
        booking_url: hotel_booking_workspace_path(hotel, booking, tab: "housekeeping_requests")
      }
    end

    def search_match?(card)
      query = params[:q].to_s.strip.downcase
      return true if query.blank?

      searchable_values = [
        card[:guest_name],
        card[:booking_token],
        card[:title],
        card[:status],
        card[:kind]
      ]

      searchable_values.compact.any? { |value| value.to_s.downcase.include?(query) } ||
        Requests::StatusGroups.aliases_for(query).include?(card[:status].to_s)
    end

    def status_match?(card)
      Requests::StatusGroups.match?(params[:status], card[:status])
    end

    def date_range_match?(card)
      date = params[:date].presence || params[:requested_on].presence
      return true if date.blank?

      requested_at = card[:requested_at_raw]
      return false if requested_at.blank?

      selected_date = begin
        Date.parse(date.to_s)
      rescue ArgumentError, TypeError
        nil
      end
      return true if selected_date.blank?

      requested_at.to_date == selected_date
    end

    def request_bucket(kind, request)
      return nil if request.status.to_s.in?(%w[cancelled no_task])
      return :completed if completed_recently?(request.completed_at, request.status)

      case kind.to_s
      when "checkout"
        :checkout unless request.completed?
      when "complaint"
        :complaint unless request.resolved?
      else
        :housekeeping unless request.completed?
      end
    end

    def completed_recently?(completed_at, status)
      return false unless status.to_s.in?(%w[completed resolved])
      return false if completed_at.blank?

      completed_at >= 7.days.ago
    end
  end
end
