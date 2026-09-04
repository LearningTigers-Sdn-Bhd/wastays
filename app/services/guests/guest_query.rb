# frozen_string_literal: true

module Guests
  class GuestQuery
    # One definition of "repeat", shared by the tab filter, the tab count, and
    # the badge on each row. Reading it off `Guest#repeat?` per row cost two
    # queries a guest.
    REPEAT_CONDITION = <<~SQL.squish
      guests.id IN (
        SELECT guest_id FROM booking_guests GROUP BY guest_id HAVING COUNT(booking_id) > 1
      ) AND guests.id IN (
        SELECT bg.guest_id FROM booking_guests bg
        INNER JOIN bookings b ON b.id = bg.booking_id
        WHERE b.status = 'completed'
      )
    SQL

    def self.repeat_ids(guest_ids)
      return Set.new if guest_ids.blank?

      Guest.where(id: guest_ids).where(REPEAT_CONDITION).pluck(:id).to_set
    end

    def initialize(hotel:, params:)
      @hotel = hotel
      @params = params
    end

    def call
      apply_filters(base_scope)
        .group("guests.id")
        .order(Arel.sql("COALESCE(MAX(bookings.checked_out_at), MAX(bookings.check_out::timestamp), guests.created_at) DESC NULLS LAST"))
    end

    # Every tab count in one round trip. The tag filter is left off so each tab
    # keeps showing its own total while another tab is open.
    def tag_counts
      row = apply_filters(base_scope, tag: nil)
        .unscope(:select)
        .select(Arel.sql([
          "COUNT(DISTINCT guests.id) AS all_count",
          "COUNT(DISTINCT guests.id) FILTER (WHERE #{vip_condition}) AS vip_count",
          "COUNT(DISTINCT guests.id) FILTER (WHERE #{REPEAT_CONDITION}) AS repeat_count",
          "COUNT(DISTINCT guests.id) FILTER (WHERE #{blacklist_condition}) AS blacklisted_count"
        ].join(", ")))
        .take

      {
        "all" => row&.all_count.to_i,
        "vip" => row&.vip_count.to_i,
        "repeat" => row&.repeat_count.to_i,
        "blacklisted" => row&.blacklisted_count.to_i
      }
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

    def base_scope
      Guest.kept
        .select("guests.*, COALESCE(MAX(bookings.checked_out_at), MAX(bookings.check_out::timestamp)) AS last_stay_at")
        .left_joins(:bookings)
        .where("bookings.hotel_id = :hotel_id OR guests.created_by_hotel_id = :hotel_id", hotel_id: @hotel.id)
    end

    def apply_filters(scope, tag: @params[:tag])
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

      return scope if tag.blank?

      case tag.to_s
      when "vip"                 then scope.where(vip_condition)
      when "blacklisted", "banned" then scope.where(blacklist_condition)
      when "repeat"              then scope.where(REPEAT_CONDITION)
      else scope
      end
    end

    # A record flagged before the per-property list existed carries the column
    # alone, so it still counts at the property that created it.
    def vip_condition
      @vip_condition ||= scoped_flag_condition(column: "vip", key: "vip_hotel_ids")
    end

    def blacklist_condition
      @blacklist_condition ||= scoped_flag_condition(column: "blacklisted", key: "blacklisted_hotel_ids")
    end

    def scoped_flag_condition(column:, key:)
      Guest.sanitize_sql_array([
        "guests.#{column} = TRUE AND (guests.metadata @> :h_json OR " \
        "(COALESCE(guests.metadata->'#{key}', '[]'::jsonb) = '[]'::jsonb AND " \
        "(guests.created_by_hotel_id IS NULL OR guests.created_by_hotel_id = :h_id)))",
        { h_json: { key => [ @hotel.id ] }.to_json, h_id: @hotel.id }
      ])
    end
  end
end
