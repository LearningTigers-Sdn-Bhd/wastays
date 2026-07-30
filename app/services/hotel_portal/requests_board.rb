# frozen_string_literal: true

module HotelPortal
  class RequestsBoard
    include Rails.application.routes.url_helpers

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

    def checkout_request_cards
      hotel.bookings
           .joins(:check_out_requests)
           .where(check_out_requests: { status: CheckOutRequest::OPEN_STATUSES })
           .includes(:check_out_requests)
           .order("check_out_requests.requested_at DESC")
           .flat_map do |booking|
             booking.check_out_requests.select(&:open_task?).map do |req|
               {
                 kind: "checkout",
                 bucket: :checkout,
                 request_id: req.id,
                 booking_id: booking.id,
                 booking_token: booking.confirmation_token,
                 guest_name: booking.guest_name,
                 room_number: req.metadata&.dig("room_number").presence || booking.booking_rooms.first&.room_number,
                 title: req.guest_notes.presence || "Checkout requested",
                 requested_at: req.requested_at,
                 status: req.metadata&.dig("workflow_status").presence || HousekeepingTasks.checkout_workflow_status_for(req.status),
                 complete_url: hotel_complete_checkout_request_path(hotel, req.id),
                 booking_url: hotel_booking_workspace_path(hotel, booking, tab: "housekeeping_requests")
               }
             end
           end
    end

    def checkout_completed_request_cards
      hotel.bookings.includes(:check_out_requests, :booking_rooms).flat_map do |booking|
        booking.check_out_requests.select { |request| request.status == "completed" && request.metadata.to_h["archived_at"].blank? }.map do |request|
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
            completed_at: request.updated_at,
            internal_notes: [],
            archive_url: hotel_archive_request_path(hotel, kind: "checkout", request_id: request.id),
            booking_url: hotel_booking_path(hotel, booking)
          }
        end
      end
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

      hotel.bookings.includes(:housekeeping_requests, :complaint_requests).each do |booking|
        booking.housekeeping_requests.active.each do |request|
          # Route checkout room cleaning requests to the checkout column instead
          # of housekeeping. This covers both checkout_request_id-linked records
          # (created by the housekeeping tasks backfill) and legacy records
          # identified by request_details.
          is_checkout_cleaning = request.metadata&.dig("checkout_request_id").present? ||
                                  request.request_details&.strip == "Checkout Room Cleaning"

          card = build_card(
            kind: is_checkout_cleaning ? "checkout" : "housekeeping",
            request: request,
            booking: booking,
            title: request.request_details
          )
          cards << card if card[:bucket].present?
        end

        booking.complaint_requests.active.each do |request|
          card = build_card(
            kind: "complaint",
            request: request,
            booking: booking,
            title: request.complaint_details
          )
          cards << card if card[:bucket].present?
        end
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
        matching_status_aliases(query).include?(card[:status].to_s)
    end

    def status_match?(card)
      status = params[:status].to_s
      return true if status.blank? || status == "all"

      case status
      when "pending"
        card[:status].in?(%w[pending in_progress failed])
      when "completed"
        card[:status].in?(%w[completed resolved])
      when "cancelled"
        card[:status] == "cancelled"
      else
        true
      end
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
      return nil if request.status.to_s == "cancelled" || request.status.to_s == "no_task"

      case kind.to_s
      when "housekeeping"
        return :completed if completed_recently?(request.completed_at, request.status)
        return nil if request.completed?
        :housekeeping
      when "checkout"
        return :completed if completed_recently?(request.completed_at, request.status)
        return nil if request.completed?
        :checkout
      when "complaint"
        return :completed if completed_recently?(request.completed_at, request.status)
        return :complaint unless request.resolved?

        nil
      else
        :housekeeping
      end
    end

    def completed_recently?(completed_at, status)
      return false unless status.to_s.in?(%w[completed resolved])
      return false if completed_at.blank?

      completed_at >= 7.days.ago
    end

    def matching_status_aliases(query)
      aliases = []
      aliases += %w[pending in_progress failed] if "pending".include?(query)
      aliases += %w[completed resolved] if "completed".include?(query) || "resolved".include?(query)
      aliases << "cancelled" if "cancelled".include?(query)
      aliases
    end
  end
end
