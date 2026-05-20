# frozen_string_literal: true

require "ostruct"

module Bookings
  class ProcessNoShows
    include Folios::NightlyChargeCalculation

    def self.call(night_audit:, user:)
      new(night_audit: night_audit, user: user).call
    end

    def initialize(night_audit:, user:)
      @night_audit = night_audit
      @hotel = night_audit.hotel
      @business_date = night_audit.business_date.to_date
      @user = user
      @processed = []
      @hotel_zone = Time.find_zone(@hotel.time_zone.presence || User::DEFAULT_TIME_ZONE) || Time.zone
    end

    def call
      no_show_candidates.find_each do |booking|
        process_booking(booking)
      end

      OpenStruct.new(success?: true, processed_count: @processed.count, bookings: @processed)
    end

    private

    def no_show_candidates
      @hotel.bookings.confirmed
        .includes(:pre_checkin, :payment_transactions, booking_rooms: :room_type, booking_folio: :folio_transactions)
        .where(check_in: @business_date)
    end

    def process_booking(booking)
      Booking.transaction do
        booking.with_lock do
          booking.reload
          next unless no_show_eligible?(booking)

          folio = Folios::InitializeForBooking.call(booking: booking, user: @user, lock: false)
          post_no_show_charges(booking, folio)
          booking.transition_status_to!("no_show", event: "mark_no_show")
          Bookings::InventoryManager.new(booking).release_by_dates(@business_date + 1.day, booking.check_out)
          release_assigned_rooms_to_ready(booking)
          Bookings::RecordAuditLog.call(
            auditable: booking,
            user: @user,
            action_type: "no_show",
            metadata: { night_audit_id: @night_audit.id, business_date: @business_date.iso8601 }
          )
          @processed << booking
        end
      end
    end

    def no_show_eligible?(booking)
      booking.status == "confirmed" &&
        booking.check_in == @business_date &&
        !active_pre_checkin_hold?(booking)
    end

    def active_pre_checkin_hold?(booking)
      pre_checkin = booking.pre_checkin
      return false unless pre_checkin&.completed?

      declared_arrival_at = declared_arrival_at_for(booking, pre_checkin)
      return false unless declared_arrival_at

      audit_reference_time < declared_arrival_at + @hotel.arrival_grace_period.seconds
    end

    def declared_arrival_at_for(booking, pre_checkin)
      arrival_time = pre_checkin.metadata&.fetch("estimated_arrival_time", nil).presence
      return nil unless arrival_time

      time_parts = arrival_time.to_s.split(":")
      return nil unless time_parts.size >= 2

      hour, minute = time_parts.first(2).map(&:to_i)
      return nil unless hour.between?(0, 23) && minute.between?(0, 59)

      arrival_date = booking.check_in.to_date
      if business_day_crosses_midnight? && seconds_since_midnight(hour, minute) <= seconds_since_midnight(@hotel.business_ends_at.hour, @hotel.business_ends_at.min)
        arrival_date += 1.day
      end

      @hotel_zone.local(arrival_date.year, arrival_date.month, arrival_date.day, hour, minute)
    end

    def audit_reference_time
      @audit_reference_time ||= (@night_audit.completed_at || @night_audit.started_at || Time.current).in_time_zone(@hotel_zone)
    end

    def business_day_crosses_midnight?
      @hotel.business_ends_at <= @hotel.business_starts_at
    end

    def seconds_since_midnight(hour, minute)
      (hour * 3600) + (minute * 60)
    end

    def release_assigned_rooms_to_ready(booking)
      booking.booking_rooms.each do |booking_room|
        next if booking_room.room_number.blank?

        room_status = RoomStatus.create_with(status: "ready").find_or_create_by!(
          hotel: booking.hotel,
          room_type: booking_room.room_type,
          room_number: booking_room.room_number
        )
        was_ready = room_status.status == "ready"

        result = Rooms::SetStatus.new(
          room_status: room_status,
          status: "ready",
          user: @user,
          booking: booking,
          event_type: "no_show_released_after_night_audit",
          reason: "Booking marked no-show after night audit",
          metadata: {
            "source" => "bookings_process_no_shows",
            "booking_id" => booking.id,
            "night_audit_id" => @night_audit.id,
            "business_date" => @business_date.iso8601
          }
        ).call

        raise result.error unless result.success?

        record_ready_room_release(room_status, booking) if was_ready
      end
    end

    def record_ready_room_release(room_status, booking)
      RoomOperationalAuditLog.create!(
        hotel: room_status.hotel,
        room_type: room_status.room_type,
        booking: booking,
        user: @user,
        room_number: room_status.room_number,
        event_type: "no_show_released_after_night_audit",
        old_status: "ready",
        new_status: "ready",
        reason: "Booking marked no-show after night audit",
        metadata: {
          "source" => "bookings_process_no_shows",
          "booking_id" => booking.id,
          "night_audit_id" => @night_audit.id,
          "business_date" => @business_date.iso8601
        }
      )
    end

    def post_no_show_charges(booking, folio)
      booking.booking_rooms.each do |booking_room|
        amount = nightly_room_amount(booking_room, @business_date)
        next if amount.zero?

        insert_charge!(
          folio: folio,
          amount: amount,
          category: "accommodation",
          description: "No-show room penalty - #{@business_date}",
          metadata: no_show_metadata(booking, "accommodation", booking_room.id).merge(
            rate_source: nightly_rate_snapshot_for(booking_room, @business_date).present? ? "nightly_rate_snapshot" : "legacy_subtotal_average",
            nightly_rate_snapshot: nightly_rate_snapshot_for(booking_room, @business_date)
          )
        )
      end

      tax_postings_for(booking, @business_date).each_with_index do |tax_line, index|
        amount = tax_line_amount(tax_line)
        next if amount.zero?

        insert_charge!(
          folio: folio,
          amount: amount,
          category: "tax",
          description: "No-show tax penalty: #{tax_line_name(tax_line)} - #{@business_date}",
          metadata: no_show_metadata(booking, "tax", tax_line_identity(tax_line, index)).merge(tax_line: tax_line)
        )
      end
    end

    def insert_charge!(folio:, amount:, category:, description:, metadata:)
      return if already_posted?(folio, metadata[:no_show_charge_key])

      result = Folios::InsertTransaction.new(
        booking_folio: folio,
        amount: amount,
        transaction_type: :charge,
        category: category,
        user: @user,
        description: description,
        posting_date: @business_date,
        options: { metadata: metadata }
      ).call

      return if result.success? || already_posted?(folio, metadata[:no_show_charge_key])

      raise "Failed to post no-show folio charge: #{result.error}"
    end

    def already_posted?(folio, no_show_charge_key)
      folio.folio_transactions.charge.where("metadata->>'no_show_charge_key' = ?", no_show_charge_key).exists?
    end

    def no_show_metadata(booking, charge_kind, identity)
      {
        posting_source: "no_show",
        night_audit_id: @night_audit.id,
        stay_date: @business_date.iso8601,
        booking_id: booking.id,
        charge_kind: charge_kind,
        no_show_charge_key: [ booking.id, @business_date.iso8601, "no_show_penalty", charge_kind, identity ].join(":")
      }
    end
  end
end
