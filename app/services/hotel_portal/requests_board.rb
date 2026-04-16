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
        booking.housekeeping_requests.each do |request|
          cards << build_card(
            kind: "housekeeping",
            request: request,
            booking: booking,
            title: request.request_details
          )
        end

        booking.complaint_requests.each do |request|
          cards << build_card(
            kind: "complaint",
            request: request,
            booking: booking,
            title: request.complaint_details
          )
        end
      end

      cards.sort_by { |card| card[:requested_at] || Time.zone.at(0) }.reverse
    end

    def build_card(kind:, request:, booking:, title:)
      {
        kind: kind,
        bucket: request_bucket(kind, request.status),
        request_id: request.id,
        booking_id: booking.id,
        booking_token: booking.confirmation_token,
        guest_name: booking.guest_name,
        title: title,
        requested_at: request.display_requested_at,
        status: request.status,
        completed_at: request.completed_at,
        update_url: hotel_request_status_path(hotel, kind: kind, request_id: request.id),
        booking_url: hotel_booking_path(hotel, booking, tab: "requests")
      }
    end

    def request_bucket(kind, status)
      case kind.to_s
      when "housekeeping"
        status.to_s == "completed" ? :completed : :housekeeping
      when "complaint"
        status.to_s == "resolved" ? :completed : :complaint
      else
        :housekeeping
      end
    end
  end
end
