# frozen_string_literal: true

module HotelPortal
  module FrontDesk
    class DeparturesQuery
      DEPARTURE_STATUSES = %w[confirmed no_show_detected checked_in checkout_required].freeze

      attr_reader :start_date, :end_date, :query

      def initialize(hotel:, params:)
        @hotel = hotel
        @start_date = parse_date(params[:departure_start_date].presence || params[:start_date])
        @end_date = parse_date(params[:departure_end_date].presence || params[:end_date].presence || @start_date)
        @start_date, @end_date = @end_date, @start_date if @end_date < @start_date
        @query = params[:departure_query].to_s.strip
      end

      def call
        scope = base_scope.includes(:booking_guests, booking_rooms: :room_type, booking_folios: [ :folio_transactions, :folio_forecasted_charges ])
        scope = apply_search(scope)
        scope.order(:check_out, :created_at, :id)
      end

      def total_count = base_scope.count

      private

      def base_scope
        @hotel.bookings
              .where(status: DEPARTURE_STATUSES)
              .checking_out_between(start_date, end_date, @hotel.hotel_time_zone)
      end

      def parse_date(value)
        Date.iso8601(value.to_s)
      rescue Date::Error
        @hotel.current_business_date || @hotel.business_date_for(Time.current)
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
