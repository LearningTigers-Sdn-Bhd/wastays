# frozen_string_literal: true

module Guests
  class GuestQuery
  def initialize(hotel:, params:)
    @hotel = hotel
    @params = params
  end

  def call
    ActiveRecord::Encryption.without_encryption do
      scope = Guest
        .select("guests.*, COALESCE(MAX(bookings.checked_out_at), MAX(bookings.check_out::timestamp)) AS last_stay_at")
        .left_joins(:bookings)
        .where("bookings.hotel_id = :hotel_id OR guests.created_by_hotel_id = :hotel_id", hotel_id: @hotel.id)

      scope = apply_filters(scope)

      scope
        .group("guests.id")
        .order(Arel.sql("COALESCE(MAX(bookings.checked_out_at), MAX(bookings.check_out::timestamp), guests.created_at) DESC NULLS LAST"))
    end
  end

  def country_options
    ActiveRecord::Encryption.without_encryption do
      Guest
        .left_joins(:bookings)
        .where("bookings.hotel_id = :hotel_id OR guests.created_by_hotel_id = :hotel_id", hotel_id: @hotel.id)
        .where.not(country: [ nil, "" ])
        .distinct
        .order(:country)
        .pluck(:country)
    end
  end

  private

  def apply_filters(scope)
    if @params[:query].present?
      query = "%#{@params[:query].to_s.downcase.strip}%"
      scope = scope.where(
        "LOWER(guests.name) LIKE :query OR LOWER(guests.email) LIKE :query OR guests.phone LIKE :query",
        query: query
      )
    end

    scope = scope.where(country: @params[:country]) if @params[:country].present?
    scope
  end
  end
end
