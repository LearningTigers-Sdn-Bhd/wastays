# frozen_string_literal: true

require "ostruct"

module ChannelManagers
  class IngestBookingService
    IngestionFailure = Class.new(StandardError)
    # Raised by callers when a revision can never be ingested without an operator
    # fixing hotel configuration first (so it lands in the failed jobs queue).
    UnprocessableBooking = Class.new(StandardError)

    def initialize(booking_data:)
      @data = booking_data
      @hotel = @data[:hotel]
    end

    def call
      conversion = ChannelManagers::ConvertBookingCurrency.new(booking_data: @data).call
      unless conversion.success?
        return OpenStruct.new(success?: false, message: conversion.message, failure_code: :missing_exchange_rate)
      end

      @data = conversion.booking_data

      if group_ingestion?
        return IngestGroupBookingService.new(booking_data: @data).call
      end

      Booking.transaction do
        @hotel.lock!
        booking = find_or_initialize_booking
        is_existing_booking = booking.persisted?
        booking.lock! if is_existing_booking
        old_audit_value = audit_values(booking)

        # 0. Basic Validation: Ensure we have enough data to even attempt ingestion
        effective_check_in = @data[:check_in] || booking.check_in
        effective_check_out = @data[:check_out] || booking.check_out

        if effective_check_in.blank? || effective_check_out.blank?
          if @data[:status] == "cancelled" && !is_existing_booking
            return OpenStruct.new(success?: true, message: "Ignored cancellation for unknown booking with no dates")
          end

          return OpenStruct.new(success?: false, message: "Missing mandatory dates (check-in/out)")
        end

        previous_check_in = booking.check_in
        previous_check_out = booking.check_out
        previous_status = booking.status

        # 1. Revision Check: Ignore older or duplicate revisions
        if is_existing_booking && duplicate_or_older_revision?(booking)
          return OpenStruct.new(success?: true, booking: booking, message: "Duplicate or older revision ignored")
        end

        incoming_status = resolved_status(effective_check_in, effective_check_out)
        incoming_status = "no_show_detected" if previous_status == "no_show_detected" && incoming_status == "confirmed"

        if is_existing_booking && previous_status != incoming_status
          event = status_transition_event_for(previous_status, incoming_status)
          return OpenStruct.new(success?: false, message: "Unsupported status transition from #{previous_status} to #{incoming_status}") unless event

          booking.status_transition_event = event
        end

        # 2. Release Old Inventory: release before mutating the booking so old dates/rooms are restored.
        if is_existing_booking && inventory_held_status?(previous_status)
          Bookings::InventoryManager.new(booking).release
        end

        # 3. Update core details
        booking.assign_attributes(
          guest_name: @data[:guest_details][:name],
          guest_email: @data[:guest_details][:email],
          guest_phone: @data[:guest_details][:phone],
          guest_country: @data[:guest_details][:country],
          check_in: Bookings::ScheduledStay.at_hotel_time(hotel: @hotel, value: effective_check_in, kind: :check_in),
          check_out: Bookings::ScheduledStay.at_hotel_time(hotel: @hotel, value: effective_check_out, kind: :check_out),
          status: incoming_status,
          adults: @data[:adults].presence || 1,
          children: @data[:children] || 0,
          total_amount: @data[:total_amount].nil? ? booking.total_amount : @data[:total_amount],
          currency: @data[:currency],
          source: @data[:source],
          external_reference: @data[:external_reference],
          channel_manager_reference: @data[:channel_manager_reference],
          revision_number: @data[:revision_number],
          payment_status: payment_status_for(booking)
        )

        if booking.save
          sync_rooms(booking) unless preserve_incomplete_cancellation_projection?
          persist_financial_snapshot!(booking)
          ChannelManagers::InitializeBookingConnections.call!(
            booking: booking,
            guest_details: @data[:guest_details]
          )
          release_detected_no_show_rooms(booking) if previous_status == "no_show_detected" && booking.status == "cancelled"

          # 5. Deduct New Inventory: If the new state is active, deduct the rooms
          if inventory_held_status?(booking.status)
            Bookings::AutoAssignRoom.new(booking: booking, source: "channel_manager").call
            Bookings::InventoryManager.new(booking).deduct
          end

          # Record Audit Log
          action = is_existing_booking ? "external_modification" : "external_creation"
          Bookings::RecordAuditLog.call!(
            auditable: booking,
            action_type: action,
            source: "channel_manager",
            old_value: old_audit_value,
            new_value: audit_values(booking),
            metadata: audit_metadata(
              source: booking.source,
              external_reference: booking.external_reference,
              revision: booking.revision_number
            )
          )

          dispatch_lifecycle_event(booking, is_existing_booking, previous_check_in, previous_check_out, previous_status)

          OpenStruct.new(success?: true, booking: booking)
        else
          raise IngestionFailure, booking.errors.full_messages.to_sentence
        end
      end
    rescue IngestionFailure => e
      OpenStruct.new(success?: false, message: e.message)
    rescue => e
      OpenStruct.new(success?: false, message: "Ingestion failed: #{e.message}")
    end

    def stay_dates_changed?(previous_check_in, previous_check_out, booking)
      previous_check_in != booking.check_in || previous_check_out != booking.check_out
    end

    private

    def audit_metadata(source:, external_reference:, revision:)
      metadata = {
        "source" => source,
        "external_reference" => external_reference,
        "revision" => revision
      }
      metadata["currency_conversion"] = @data[:currency_conversion] if @data[:currency_conversion].present?
      metadata
    end

    def duplicate_or_older_revision?(booking)
      revision_id = @data[:revision_id].to_s
      if revision_id.present? && !revision_id.match?(/\A\d+\z/)
        return true if OtaFinancialSnapshot.exists?(booking: booking, provider_revision_id: revision_id)

        snapshot = OtaFinancialSnapshot.current.find_by(booking: booking)
        if snapshot
          return true if snapshot.provider_revision_id == revision_id
          return true if @data[:revision_number].to_i < booking.revision_number.to_i
        end
        return false
      end

      booking.revision_number.to_i >= @data[:revision_number].to_i
    end

    def group_ingestion?
      total_room_quantity > 1 || GroupBooking.exists?(
        hotel: @hotel,
        channel_manager_reference: @data[:channel_manager_reference]
      )
    end

    def total_room_quantity
      Array(@data[:rooms]).sum { |room| [ room[:quantity].to_i, 1 ].max }
    end

    def find_or_initialize_booking
      @hotel.bookings.find_by(channel_manager_reference: @data[:channel_manager_reference]) ||
        @hotel.bookings.new(channel_manager_reference: @data[:channel_manager_reference])
    end

    def inventory_insufficient?(check_in, check_out)
      (check_in.to_date...check_out.to_date).each do |date|
        @data[:rooms].each do |room_item|
          inventory = room_item[:room_type].room_inventories.lock.find_by(date: date)
          return true if !inventory || inventory.quantity < room_item[:quantity]
        end
      end
      false
    end

    def resolved_status(check_in, check_out)
      return @data[:status] if @data[:status] == "cancelled"
      return "overbooked" if inventory_insufficient?(check_in, check_out)

      @data[:status]
    end

    def release_inventory(rooms, check_in, check_out)
      return if check_in.blank? || check_out.blank?

      rooms.each do |room|
        (check_in.to_date...check_out.to_date).each do |date|
          inventory = room[:room_type].room_inventories.lock.find_by(date: date)
          inventory&.update!(quantity: inventory.quantity + room[:quantity])
        end
      end
    end

    def inventory_held_status?(status)
      status.in?(%w[confirmed no_show_detected checked_in due_out_detected checkout_required])
    end

    def release_detected_no_show_rooms(booking)
      result = Bookings::ReleaseAssignedRooms.call(
        booking: booking,
        user: nil,
        event_type: "no_show_detection_cancelled",
        reason: "Channel manager cancelled booking with detected no-show",
        metadata: { "source" => "channel_manager", "external_reference" => booking.external_reference }
      )
      raise IngestionFailure, result.error unless result.success?
    end

    def status_transition_event_for(previous_status, new_status)
      case [ previous_status, new_status ]
      when [ "pending", "confirmed" ]
        "confirm"
      when [ "pending", "cancelled" ], [ "confirmed", "cancelled" ], [ "overbooked", "cancelled" ]
        "cancel"
      when [ "no_show_detected", "cancelled" ]
        "cancel"
      when [ "confirmed", "overbooked" ]
        "mark_overbooked"
      when [ "overbooked", "confirmed" ]
        "resolve_overbooking"
      else
        nil
      end
    end

    def payment_status_for(booking)
      status = @data[:payment_status].presence || @data.dig(:payment, :status).presence
      return status if Booking::PAYMENT_STATUSES.include?(status.to_s)
      booking.payment_status.presence || "pending"
    end

    def dispatch_lifecycle_event(booking, is_existing_booking, previous_check_in, previous_check_out, previous_status)
      event = lifecycle_event_for(booking, is_existing_booking, previous_check_in, previous_check_out, previous_status)
      return unless event

      Bookings::WebhookTriggerService.new(booking).trigger(event)
      Notifications::Dispatcher.new(event: event, booking: booking).call
    end

    def lifecycle_event_for(booking, is_existing_booking, previous_check_in, previous_check_out, previous_status)
      return :booking_cancelled if booking.status == "cancelled" && previous_status != "cancelled"
      return :booking_confirmed if !is_existing_booking && booking.status == "confirmed"
      return :booking_updated if stay_dates_changed?(previous_check_in, previous_check_out, booking)
      return :booking_updated if previous_status != booking.status

      nil
    end

    def preserve_incomplete_cancellation_projection?
      @data[:status] == "cancelled" && @data[:financials].present? && !complete_financials?
    end

    def sync_rooms(booking)
      # For modifications, we'll just recreate room items for now. Physical room
      # assignments are carried over so an unrelated revision never moves a guest.
      assigned_room_numbers = assigned_room_numbers_by_room_type(booking)
      existing_rooms = booking.booking_rooms.to_a

      @data[:rooms].each_with_index do |room_item, room_index|
        qty = [ room_item[:quantity].to_i, 1 ].max
        qty.times do |unit_index|
          financial_room = Array(@data.dig(:financials, :rooms))[room_index]
          room = existing_rooms.find { |candidate| candidate.room_type_id == room_item[:room_type]&.id } || existing_rooms.first
          room ||= booking.booking_rooms.build
          existing_rooms.delete(room)
          room.update!(
            room_type: posted_nightly_history?(booking) && room.persisted? ? room.room_type : room_item[:room_type],
            rate_plan: posted_nightly_history?(booking) && room.persisted? ? room.rate_plan : room_item[:rate_plan],
            subtotal: (room_item[:amount].to_d / qty).round(2),
            occupancy_snapshot: financial_room&.dig(:occupancy) || room_item[:occupancy] || {},
            nightly_rate_snapshot: nightly_snapshot_for(financial_room, qty, unit_index, booking, room.nightly_rate_snapshot),
            room_number: room.room_number.presence || assigned_room_numbers[room_item[:room_type]&.id].shift
          )
        end
      end
      existing_rooms.each do |room|
        room.destroy! unless OtaFinancialComponent.exists?(booking_room: room)
      end
    end

    def nightly_snapshot_for(financial_room, quantity, unit_index, booking, existing_snapshot)
      incoming = Array(financial_room&.dig(:days)).to_h do |day|
        amount = allocate_unit_amount(day[:converted_amount] || day[:amount], quantity, unit_index)
        [ day[:date].to_s, { "date" => day[:date].to_s, "price" => amount.to_d.to_s("F"),
          "currency" => @data[:currency], "source" => "ota_supplied" } ]
      end
      preserve_posted_nights(booking, existing_snapshot, incoming)
    end

    def preserve_posted_nights(booking, existing_snapshot, incoming)
      existing = existing_snapshot.to_h
      incoming.merge(existing.slice(*posted_nightly_dates(booking)))
    end

    def posted_nightly_history?(booking)
      posted_nightly_dates(booking).any?
    end

    def posted_nightly_dates(booking)
      @posted_nightly_dates ||= {}
      @posted_nightly_dates[booking.id] ||= FolioTransaction.joins(:booking_folio)
        .where(booking_folios: { booking_id: booking.id }, voided_by_transaction_id: nil)
        .where("folio_transactions.metadata->>'nightly_charge_key' IS NOT NULL")
        .distinct.pluck(Arel.sql("COALESCE(folio_transactions.metadata->>'stay_date', folio_transactions.posting_date::text)"))
    end

    def allocate_unit_amount(amount, quantity, unit_index)
      unit = (amount.to_d / quantity).round(CurrencyCatalog.precision_for(@data[:currency]))
      unit_index == quantity - 1 ? amount.to_d - unit * (quantity - 1) : unit
    end

    def persist_financial_snapshot!(booking)
      return unless complete_financials?

      ChannelManagers::Financials::PersistSnapshot.call!(financials: @data[:financials], booking: booking)
    end

    def complete_financials?
      @data.dig(:financials, :breakdown_complete) == true
    end

    def assigned_room_numbers_by_room_type(booking)
      booking.booking_rooms.each_with_object(Hash.new { |numbers, key| numbers[key] = [] }) do |room, numbers|
        next if room.room_number.blank?

        numbers[room.room_type_id] << room.room_number
      end
    end

    def audit_values(booking)
      rooms_grouped = booking.booking_rooms.group_by { |room| room_summary(room) }
      rooms_array = rooms_grouped.map do |summary, rooms|
        rooms.size > 1 ? "#{rooms.size}x #{summary}" : summary
      end

      booking.slice(
        "guest_name", "guest_email", "guest_phone", "guest_country", "check_in", "check_out",
        "status", "adults", "total_amount", "currency", "payment_status"
      ).merge("rooms" => rooms_array)
    end

    def room_summary(room)
      parts = [ room.room_type&.name || "Room category not provided" ]
      parts << room.rate_plan.name if room.rate_plan
      parts.join(" - ")
    end
  end
end
