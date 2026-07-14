# frozen_string_literal: true

require "ostruct"

module BookingEngine
  class ConfirmBooking
    def initialize(quote_token:, payment_details:)
      @quote = BookingQuote.find_by!(token: quote_token)
      @payment_details = payment_details # Hash from GatewayAdapter
    end

    def call
      @quote.with_lock do
        if multi_room_quote?
          return BookingEngine::ConfirmGroupBooking.call(quote: @quote, payment_details: @payment_details)
        end

        if (booking = existing_booking)
          initialize_folio(booking)
          return OpenStruct.new(success?: true, booking: booking)
        end

        # 1. Double check quote haven't expired (though it should have been held)
        if quote_expired?
          expire_quote!
          return OpenStruct.new(success?: false, message: "Quote has expired.")
        end

        reservation_num = HotelCounter.increment!(hotel: @quote.hotel, type: "reservation")
        receipt_num     = HotelCounter.increment!(hotel: @quote.hotel, type: "receipt")

        # 2. Create Booking from Quote snapshots
        margin_rate = @quote.hotel.effective_margin_rate
        margin_amount = (@quote.total_amount * (margin_rate / 100.0)).round(2)

        guest_country = normalize_country(@payment_details[:country])
        gender = @payment_details[:gender]&.downcase&.strip
        document_type = @payment_details[:document_type]&.downcase&.strip

        financial_snapshot = Bookings::BuildFinancialSnapshot.new(
          hotel: @quote.hotel,
          check_in: Bookings::ScheduledStay.at_hotel_time(hotel: @quote.hotel, value: @quote.check_in, kind: :check_in),
          check_out: Bookings::ScheduledStay.at_hotel_time(hotel: @quote.hotel, value: @quote.check_out, kind: :check_out),
          guest_country: guest_country,
          room_items: @quote.booking_quote_items.map do |item|
            {
              quantity: item.quantity,
              nightly_rate_snapshot: item.nightly_rate_snapshot
            }
          end
        ).call

        tax_lines = financial_snapshot.tax_lines
        tourism_tax = tax_lines.find { |tax| tax["type"].to_s == "tourism_tax" }
        tourism_tax_amount = tourism_tax ? tourism_tax["amount"].to_d : 0
        payable_total = financial_snapshot.room_total + Booking.non_tourism_tax_total_for(tax_lines)

        booking = Booking.new(
          booking_quote: @quote,
          hotel: @quote.hotel,
          guest_name: @payment_details[:guest_name], # From checkout form
          guest_email: @payment_details[:guest_email],
          guest_phone: @payment_details[:guest_phone],
          special_requests: @payment_details[:special_requests],
          total_amount: payable_total,
          currency: @quote.currency,
          check_in: @quote.check_in,
          check_out: @quote.check_out,
          adults: @quote.adults,
          children: @quote.children,
          hotel_snapshot: @quote.hotel_snapshot,
          cancellation_policy_snapshot: @quote.cancellation_policy_snapshot,
          status: "confirmed",
          payment_status: "captured",
          margin_rate: margin_rate,
          margin_amount: margin_amount,
          net_amount: payable_total - margin_amount,
          guest_gender: gender,
          guest_country: guest_country,
          guest_document_type: document_type,
          tourism_tax_amount: tourism_tax_amount,
          tourism_tax_applied: tourism_tax_amount.positive?,
          tax_lines: tax_lines,
          tax_posting_snapshot: financial_snapshot.tax_posting_snapshot,
          reservation_number: reservation_num,
          receipt_number: receipt_num,
          hotel_corporate_account_id: @quote.hotel_corporate_account_id
        )


        @quote.booking_quote_items.each do |item|
          rate_plan_id = nil
          if item.nightly_rate_snapshot.present?
            first_rate_data = item.nightly_rate_snapshot.values.first
            rate_plan_id = first_rate_data["rate_plan_id"] if first_rate_data.is_a?(Hash)
          end

          item.quantity.times do
            booking.booking_rooms.build(
              room_type: item.room_type,
              rate_plan_id: rate_plan_id,
              subtotal: (item.subtotal.to_d / item.quantity).round(2),
              room_type_snapshot: item.room_type_snapshot,
              nightly_rate_snapshot: normalized_nightly_rate_snapshot(item.nightly_rate_snapshot),
              occupancy_snapshot: item.occupancy_snapshot
            )
          end
        end

        if booking.save
          # 3. Link Guest Profile
          guest_result = GuestArrival::CreateOrMatchGuest.new(
            name: @payment_details[:guest_name],
            email: @payment_details[:guest_email],
            phone: @payment_details[:guest_phone],
            government_id: @payment_details[:guest_government_id],
            gender: gender,
            country: guest_country,
            document_type: document_type,
            date_of_birth: @payment_details[:date_of_birth],
            marketing_consent: @payment_details[:marketing_consent],
            privacy_consent: @payment_details[:privacy_consent]
          ).call

          if guest_result.success?
            booking.booking_guests.create!(guest: guest_result.guest, is_primary: true)
          end

          # 4. Initialize Pre-checkin
          GuestArrival::StartPreCheckin.new(booking).call

          initialize_folio(booking)

          # 4. Finalize Quote status
          @quote.update!(status: "converted", special_requests: @payment_details[:special_requests])

          # Record Audit Logs
          Bookings::RecordAuditLog.call!(auditable: @quote, action_type: "convert", source: "guest")
          Bookings::RecordAuditLog.call!(auditable: booking, action_type: "create", source: "guest")

          # 5. Trigger Webhooks
          Bookings::WebhookTriggerService.new(booking).trigger(:booking_confirmed)
          Notifications::Dispatcher.new(event: :booking_confirmed, booking: booking).call

          # 6. Dispatch Guest Notifications
          # Notifications::BookingConfirmedJob.perform_later(booking.id)
          OpenStruct.new(success?: true, booking: booking)
        else
          OpenStruct.new(success?: false, message: booking.errors.full_messages.to_sentence)
        end
      end
    rescue => e
      OpenStruct.new(success?: false, message: "Confirmation failed: #{e.message}")
    end

    private

    def multi_room_quote?
      @quote.booking_quote_items.sum(:quantity) > 1
    end

    def existing_booking
      Booking.find_by(booking_quote_id: @quote.id)
    end

    def initialize_folio(booking)
      Folios::InitializeForBooking.call(
        booking: booking,
        user: nil,
        options: {
          system_folio_initialization: true,
          posting_source: "booking_confirmation"
        },
        lock: false
      )
    end

    def normalized_nightly_rate_snapshot(snapshot)
      snapshot.to_h.transform_keys(&:to_s).transform_values do |value|
        value.respond_to?(:to_h) ? value.to_h.transform_keys(&:to_s) : { "price" => value }
      end
    end

    def quote_expired?
      @quote.status == "expired" || @quote.expires_at <= Time.current
    end

    def expire_quote!
      return if @quote.status == "expired"

      @quote.booking_quote_items.includes(:room_type).each do |item|
        (@quote.check_in...@quote.check_out).each do |date|
          inventory = item.room_type.room_inventories.lock.find_by(date: date)
          inventory&.update!(quantity: inventory.quantity + item.quantity)
        end
      end

      @quote.update!(status: "expired")
      Bookings::RecordAuditLog.call(auditable: @quote, action_type: "expire")
    end

    def normalize_country(value)
      return if value.blank?

      country = ISO3166::Country.find_country_by_any_name(value.to_s.strip)
      country&.iso_short_name || value.to_s.split.map(&:capitalize).join(" ")
    rescue StandardError
      value.to_s.split.map(&:capitalize).join(" ")
    end
  end
end
