# frozen_string_literal: true

module HotelPortal
  class HousekeepingRequestsSearchQuery
    def initialize(relation = HousekeepingRequest.all, query:)
      @relation = relation
      @query = query.to_s.strip
    end

    def call
      return @relation if @query.blank?

      q = "%#{ActiveRecord::Base.sanitize_sql_like(@query.downcase)}%"
      @relation.joins(:booking)
        .left_joins(booking: :booking_rooms)
        .where(
          "housekeeping_requests.external_id ILIKE :q OR " \
          "housekeeping_requests.request_details ILIKE :q OR " \
          "bookings.confirmation_token ILIKE :q OR " \
          "bookings.guest_name ILIKE :q OR " \
          "bookings.guest_email ILIKE :q OR " \
          "bookings.guest_phone ILIKE :q OR " \
          "housekeeping_requests.room_number ILIKE :q OR " \
          "booking_rooms.room_number ILIKE :q",
          q: q
        ).distinct
    end
  end
end
