module HotelPortal
  class RequestsBoard
    include Rails.application.routes.url_helpers

    attr_reader :hotel

    def initialize(hotel)
      @hotel = hotel
    end

    def board_columns
      @board_columns ||= {
        housekeeping: request_cards.select { |card| card[:bucket] == :housekeeping },
        complaint: request_cards.select { |card| card[:bucket] == :complaint },
        completed: request_cards.select { |card| card[:bucket] == :completed }
      }
    end

    def board_counts
      board_columns.transform_values(&:count)
    end

    private

    def request_cards
      @request_cards ||= build_request_cards
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
        status: request.status,
        completed_at: request.completed_at,
        archive_url: hotel_archive_request_path(hotel, kind: kind, request_id: request.id),
        update_url: hotel_request_status_path(hotel, kind: kind, request_id: request.id),
        booking_url: hotel_booking_path(hotel, booking, tab: "requests")
      }
    end

    def request_bucket(kind, request)
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
