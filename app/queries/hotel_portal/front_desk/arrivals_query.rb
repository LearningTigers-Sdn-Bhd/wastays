# frozen_string_literal: true

module HotelPortal
  module FrontDesk
    class ArrivalsQuery
      attr_reader :start_date, :end_date, :query

      def initialize(hotel:, params:)
        @hotel = hotel
        @start_date = parse_date(params[:arrival_start_date].presence || params[:start_date].presence || params[:arrival_date])
        @end_date = parse_date(params[:arrival_end_date].presence || params[:end_date].presence || @start_date)
        @start_date, @end_date = @end_date, @start_date if @end_date < @start_date
        @query = params[:arrival_q].to_s.strip
      end

      def call
        scope = base_scope.includes(:booking_rooms, :pre_checkin, :booking_notes, booking_guests: { guest: :bookings }, booking_folios: [ :folio_transactions, :folio_forecasted_charges ])
        scope = apply_search(scope)
        scope.order(created_at: :asc, id: :asc)
      end

      def total_count = base_scope.count
      private

      def base_scope
        @hotel.bookings.active.checking_in_between(start_date, end_date, @hotel.hotel_time_zone)
      end

      def parse_date(value)
        Date.iso8601(value.to_s)
      rescue Date::Error
        Time.current.in_time_zone(@hotel.hotel_time_zone).to_date
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
