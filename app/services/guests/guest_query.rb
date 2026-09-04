# frozen_string_literal: true

module Guests
  class GuestQuery
  def initialize(hotel:, params:)
    @hotel = hotel
    @params = params
  end

  def call
    scope = Guest.kept
      .select("guests.*, COALESCE(MAX(bookings.checked_out_at), MAX(bookings.check_out::timestamp)) AS last_stay_at")
      .left_joins(:bookings)
      .where("bookings.hotel_id = :hotel_id OR guests.created_by_hotel_id = :hotel_id", hotel_id: @hotel.id)

    scope = apply_filters(scope)

    scope
      .group("guests.id")
      .order(Arel.sql("COALESCE(MAX(bookings.checked_out_at), MAX(bookings.check_out::timestamp), guests.created_at) DESC NULLS LAST"))
  end

  def country_options
    Guest.kept
      .left_joins(:bookings)
      .where("bookings.hotel_id = :hotel_id OR guests.created_by_hotel_id = :hotel_id", hotel_id: @hotel.id)
      .where.not(country: [ nil, "" ])
      .distinct
      .order(:country)
      .pluck(:country)
  end

  private

  def apply_filters(scope)
    if @params[:query].present?
      raw_query = @params[:query].to_s.downcase.strip
      query = "%#{raw_query}%"

      search_conditions = Guest.where(
        "LOWER(guests.name) LIKE :query OR LOWER(bookings.guest_email) LIKE :query OR bookings.guest_phone LIKE :query",
        query: query
      )

      # Support exact matches on encrypted guest fields (requires deterministic encryption)
      search_conditions = search_conditions.or(Guest.where(email: raw_query))
                                           .or(Guest.where(phone: raw_query))
                                           .or(Guest.where(government_id: raw_query))

      scope = scope.merge(search_conditions)
    end

    scope = scope.where(country: @params[:country]) if @params[:country].present?

    if @params[:tag].present?
      case @params[:tag].to_s
      when "vip"
        scope = scope.where(vip: true).where(
          "guests.metadata @> :h_json OR (COALESCE(guests.metadata->'vip_hotel_ids', '[]'::jsonb) = '[]'::jsonb AND (guests.created_by_hotel_id IS NULL OR guests.created_by_hotel_id = :h_id))",
          h_json: { vip_hotel_ids: [ @hotel.id ] }.to_json,
          h_id: @hotel.id
        )
      when "blacklisted", "banned"
        scope = scope.where(blacklisted: true).where(
          "guests.metadata @> :h_json OR (COALESCE(guests.metadata->'blacklisted_hotel_ids', '[]'::jsonb) = '[]'::jsonb AND (guests.created_by_hotel_id IS NULL OR guests.created_by_hotel_id = :h_id))",
          h_json: { blacklisted_hotel_ids: [ @hotel.id ] }.to_json,
          h_id: @hotel.id
        )
      when "repeat"
        scope = scope.where(id: BookingGuest.group(:guest_id).having("COUNT(booking_id) > 1").select(:guest_id))
                     .where(id: BookingGuest.joins(:booking).where(bookings: { status: "completed" }).select(:guest_id))
      end
    end

    scope
  end
  end
end
