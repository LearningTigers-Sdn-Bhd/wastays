# frozen_string_literal: true

module HotelPortal
  class InHouseGuestsQuery
    def initialize(hotel:, params:)
      @hotel = hotel
      @params = params
    end

    def call
      scope = base_scope.includes(:booking_rooms, :guests, :booking_guests)
      scope = apply_search(scope)
      scope = apply_room_assignment_filter(scope)
      scope.order(checked_in_at: :desc, created_at: :desc)
    end

    def in_house_count
      base_scope.count
    end

    def check_outs_today_count
      base_scope.checking_out_on(Date.current, @hotel.hotel_time_zone).count
    end

    private

    def base_scope
      @hotel.bookings
            .where(status: [ "checked_in", "review_due_out", "checkout_required" ])
            .where.not(checked_in_at: nil)
            .where(checked_out_at: nil)
    end

    def apply_search(scope)
      query = @params[:query].to_s.strip
      return scope if query.blank?

      search_term = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      scope.where(
        "guest_name ILIKE :search OR guest_email ILIKE :search OR guest_phone ILIKE :search OR confirmation_token ILIKE :search",
        search: search_term
      )
    end

    def apply_room_assignment_filter(scope)
      case @params[:room_assignment].to_s
      when "assigned"
        scope.left_outer_joins(:booking_rooms).where.not(booking_rooms: { id: nil }).distinct
      when "unassigned"
        scope.left_outer_joins(:booking_rooms).where(booking_rooms: { id: nil })
      else
        scope
      end
    end
  end
end
