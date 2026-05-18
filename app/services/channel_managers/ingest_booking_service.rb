# frozen_string_literal: true

require "ostruct"

module ChannelManagers
  class IngestBookingService
    def initialize(booking_data:)
      @data = booking_data
      @hotel = @data[:hotel]
    end

    def call
      Booking.transaction do
        @hotel.lock!
        booking = find_or_initialize_booking
        is_existing_booking = booking.persisted?
        booking.lock! if is_existing_booking

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
        if is_existing_booking && booking.revision_number.to_i >= @data[:revision_number].to_i
          return OpenStruct.new(success?: true, booking: booking, message: "Duplicate or older revision ignored")
        end

        # 2. Release Old Inventory: If this is an existing active booking, release its current rooms before applying changes
        if is_existing_booking && inventory_held_status?(previous_status)
          Bookings::InventoryManager.new(booking).release
        end

        # 3. Update core details
        booking.assign_attributes(
          guest_name: @data[:guest_details][:name],
          guest_email: @data[:guest_details][:email],
          guest_phone: @data[:guest_details][:phone],
          guest_country: @data[:guest_details][:country],
          check_in: effective_check_in,
          check_out: effective_check_out,
          status: @data[:status],
          adults: @data[:adults] || 1,
          total_amount: @data[:total_amount],
          currency: @data[:currency],
          source: @data[:source],
          external_reference: @data[:external_reference],
          channel_manager_reference: @data[:channel_manager_reference],
          revision_number: @data[:revision_number],
          payment_status: payment_status_for(booking)
        )

        # 4. Handle Overbooking Logic
        if booking.status != "cancelled" && inventory_insufficient?(booking)
          booking.status = "overbooked"
        end

        if booking.save
          sync_guest(booking)
          sync_rooms(booking)

          # 5. Deduct New Inventory: If the new state is active, deduct the rooms
          if inventory_held_status?(booking.status)
            Bookings::InventoryManager.new(booking).deduct
          end

          # Record Audit Log
          action = is_existing_booking ? "external_modification" : "external_creation"
          Bookings::RecordAuditLog.call(
            auditable: booking,
            action_type: action,
            metadata: { "source" => booking.source, "external_reference" => booking.external_reference, "revision" => booking.revision_number }
          )

          dispatch_lifecycle_event(booking, is_existing_booking, previous_check_in, previous_check_out, previous_status)

          OpenStruct.new(success?: true, booking: booking)
        else
          OpenStruct.new(success?: false, message: booking.errors.full_messages.to_sentence)
        end
      end
    rescue => e
      OpenStruct.new(success?: false, message: "Ingestion failed: #{e.message}")
    end

    def stay_dates_changed?(previous_check_in, previous_check_out, booking)
      previous_check_in != booking.check_in || previous_check_out != booking.check_out
    end

    private

    def find_or_initialize_booking
      Booking.find_by(channel_manager_reference: @data[:channel_manager_reference]) ||
        Booking.new(hotel: @hotel, channel_manager_reference: @data[:channel_manager_reference])
    end

    def inventory_insufficient?(booking)
      (@data[:check_in]..(@data[:check_out] - 1.day)).each do |date|
        @data[:rooms].each do |room_item|
          inventory = room_item[:room_type].room_inventories.lock.find_by(date: date)
          return true if !inventory || inventory.quantity < room_item[:quantity]
        end
      end
      false
    end

    def release_inventory(rooms, check_in, check_out)
      return if check_in.blank? || check_out.blank?

      rooms.each do |room|
        (check_in...check_out).each do |date|
          inventory = room[:room_type].room_inventories.lock.find_by(date: date)
          inventory&.update!(quantity: inventory.quantity + room[:quantity])
        end
      end
    end

    def inventory_held_status?(status)
      status.in?(%w[confirmed checked_in])
    end

    def payment_status_for(booking)
      status = @data[:payment_status].presence || @data.dig(:payment, :status).presence
      return status if Booking::PAYMENT_STATUSES.include?(status.to_s)
      return "refunded" if @data[:status] == "cancelled" && booking.payment_status == "captured"

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

    def sync_guest(booking)
      guest_result = GuestArrival::CreateOrMatchGuest.new(
        name: @data[:guest_details][:name],
        email: @data[:guest_details][:email],
        phone: @data[:guest_details][:phone],
        country: @data[:guest_details][:country]
      ).call

      if guest_result.success? && !booking.booking_guests.exists?(guest: guest_result.guest)
        booking.booking_guests.create!(guest: guest_result.guest, is_primary: true)
      end
    end

    def sync_rooms(booking)
      # For modifications, we'll just recreate room items for now
      booking.booking_rooms.destroy_all

      @data[:rooms].each do |room_item|
        booking.booking_rooms.create!(
          room_type: room_item[:room_type],
          rate_plan: room_item[:rate_plan],
          quantity: room_item[:quantity],
          subtotal: room_item[:amount]
          # snapshots to be added if needed
        )
      end
    end
  end
end
