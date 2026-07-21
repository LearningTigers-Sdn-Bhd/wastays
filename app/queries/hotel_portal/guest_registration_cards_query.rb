# frozen_string_literal: true

module HotelPortal
  class GuestRegistrationCardsQuery
    attr_reader :hotel, :start_date, :end_date, :status, :query, :page

    def initialize(hotel:, start_date: nil, end_date: nil, status: nil, query: nil, page: nil)
      @hotel = hotel
      @start_date = start_date
      @end_date = end_date
      @status = status.to_s
      @query = query&.to_s&.strip
      @page = page
    end

    def base_scope
      @base_scope ||= begin
        scope = hotel.guest_registration_cards
                     .includes(:hotel, booking: :booking_rooms)
                     .joins(:booking)
        scope = scope.where(bookings: { check_in: start_date.beginning_of_day..end_date.end_of_day }) if start_date && end_date
        scope
      end
    end

    def total_count
      base_scope.count
    end

    def signed_count
      base_scope.where(status: "signed").count
    end

    def draft_count
      base_scope.where(status: "draft").count
    end

    def results
      scope = base_scope.order("bookings.check_in DESC")
      scope = scope.where(status: status) if %w[draft signed].include?(status)

      if query.present?
        sanitize_query = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
        compact_query = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase.delete("-"))}%"
        hotel_prefix = ActiveRecord::Base.connection.quote(hotel.hotel_prefix.to_s.downcase)
        formatted_grc_sql = "LOWER(CONCAT(#{hotel_prefix}, '-2', LPAD(CAST(bookings.guest_registration_number AS TEXT), 7, '0')))"
        scope = scope.where(
          "LOWER(bookings.guest_name) LIKE :query OR LOWER(bookings.confirmation_token) LIKE :query OR CAST(bookings.guest_registration_number AS TEXT) LIKE :query OR #{formatted_grc_sql} LIKE :query OR REPLACE(#{formatted_grc_sql}, '-', '') LIKE :compact_query",
          compact_query: compact_query,
          query: sanitize_query
        )
      end

      page.present? ? scope.page(page).per(25) : scope
    end
  end
end
