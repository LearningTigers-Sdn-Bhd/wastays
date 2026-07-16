# frozen_string_literal: true

module HotelPortal
  module FrontDesk
    class DeparturesQuery
      attr_reader :start_date, :end_date, :query

      def initialize(hotel:, params:)
        @hotel = hotel
        @start_date = parse_date(params[:start_date])
        @end_date = parse_date(params[:end_date].presence || @start_date)
        @start_date, @end_date = @end_date, @start_date if @end_date < @start_date
        @query = params[:departure_query].to_s.strip
      end

      def call
        scope = base_scope.includes(booking_rooms: :room_type, booking_folios: :folio_transactions).includes(:guests, :booking_guests)
        scope = apply_search(scope)
        scope.order(checked_out_at: :desc, created_at: :desc)
      end

      def total_count = base_scope.count

      private

      def base_scope
        range = start_date.in_time_zone(@hotel.hotel_time_zone).beginning_of_day..end_date.in_time_zone(@hotel.hotel_time_zone).end_of_day
        @hotel.bookings.completed.where(checked_out_at: range)
      end

      def parse_date(value)
        Date.iso8601(value.to_s)
      rescue Date::Error
        Date.current
      end

      def apply_search(scope)
        return scope if query.blank?

        search = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
        scope.where(
          "guest_name ILIKE :search OR guest_email ILIKE :search OR guest_phone ILIKE :search OR confirmation_token ILIKE :search",
          search:
        )
      end
    end
  end
end
