# frozen_string_literal: true

module HotelPortal
  module FrontDesk
    class BookingsQuery
      STATUSES = (Booking::STATUSES - [ "overbooked" ]).freeze

      attr_reader :query, :status, :start_date, :end_date

      def initialize(hotel:, params:)
        @hotel = hotel
        @query = params[:booking_query].to_s.strip
        @status = params[:booking_status].presence_in(STATUSES)
        @start_date = parse_date(params[:booking_start_date].presence || params[:booking_check_in_date].presence || params[:start_date]) if params[:booking_start_date].present? || params[:booking_check_in_date].present? || params[:start_date].present?
        @end_date = parse_date(params[:booking_end_date].presence || params[:end_date]) if params[:booking_end_date].present? || params[:end_date].present?
        @start_date ||= @end_date
        @end_date ||= @start_date
        @start_date, @end_date = @end_date, @start_date if @start_date && @end_date && @end_date < @start_date
      end

      def call
        scope = @hotel.bookings.recent_first.includes(booking_rooms: :room_type, booking_folios: :folio_transactions, booking_guests: :guest)
        scope = scope.search(query) if query.present?
        scope = scope.where(status:) if status.present?
        scope = scope.checking_in_between(start_date, end_date, @hotel.hotel_time_zone) if start_date
        scope
      end

      private

      def parse_date(value)
        Date.iso8601(value.to_s)
      rescue Date::Error
        Date.current
      end
    end
  end
end
