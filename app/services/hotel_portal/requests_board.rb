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
          completed: cards.select { |card| card[:bucket] == :completed }
                          .sort_by { |card| card[:completed_at] || Time.zone.at(0) }
                          .reverse
        }
      end
    end

    def board_counts
      board_columns.transform_values(&:count)
    end

    private

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
          card = build_card(
            kind: "housekeeping",
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
        title: title,
        requested_at: request.display_requested_at,
        requested_at_raw: request.display_requested_at,
        status: request.status,
        completed_at: request.completed_at,
        internal_notes: request.respond_to?(:internal_notes_list) ? request.internal_notes_list : [],
        archive_url: hotel_archive_request_path(hotel, kind: kind, request_id: request.id),
        update_url: hotel_request_status_path(hotel, kind: kind, request_id: request.id),
        booking_url: hotel_booking_path(hotel, booking, tab: "requests")
      }
    end
def search_match?(card)
  query = params[:q].to_s.strip.downcase
  return true if query.blank?

  # Map query to potential statuses if it matches a group name
  status_aliases = []
  if "pending".include?(query)
    status_aliases += %w[pending in_progress failed]
  end
  if "completed".include?(query) || "resolved".include?(query)
    status_aliases += %w[completed resolved]
  end
  if "cancelled".include?(query)
    status_aliases << "cancelled"
  end

  searchable_values = [
    card[:guest_name],
    card[:booking_token],
    card[:title],
    card[:status],
    card[:kind]
  ]

  # Check if query matches any searchable value OR if the card status matches a status alias
  searchable_values.compact.any? { |value| value.to_s.downcase.include?(query) } ||
    status_aliases.include?(card[:status].to_s)
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
      return nil if request.status.to_s == "cancelled"

      case kind.to_s
      when "housekeeping"
        return :completed if completed_recently?(request.completed_at, request.status)
        return :housekeeping unless request.completed?

        nil
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
  end
end
