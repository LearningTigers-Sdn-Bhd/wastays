require "ostruct"

module BookingEngine
  class ConfirmBooking
    def initialize(quote_token:, payment_details:)
      @quote = BookingQuote.find_by!(token: quote_token)
      @payment_details = payment_details # Hash from GatewayAdapter
    end

    def call
      return OpenStruct.new(success?: true, booking: existing_booking) if existing_booking

      # Pre-assign sequential numbers outside the transaction to avoid nested lock conflicts
      reservation_num = HotelCounter.increment!(hotel: @quote.hotel, type: "reservation")
      receipt_num     = HotelCounter.increment!(hotel: @quote.hotel, type: "receipt")

      Booking.transaction do
        # 1. Double check quote haven't expired (though it should have been held)
        if @quote.status == "expired"
          return OpenStruct.new(success?: false, message: "Quote has expired.")
        end

        # 2. Create Booking from Quote snapshots
        margin_rate = @quote.hotel.effective_margin_rate
        margin_amount = (@quote.total_amount * (margin_rate / 100.0)).round(2)
        net_amount = @quote.total_amount - margin_amount

        guest_country = normalize_country(@payment_details[:country])
        gender = @payment_details[:gender]&.downcase&.strip
        document_type = @payment_details[:document_type]&.downcase&.strip

        rooms_subtotal = @quote.booking_quote_items.sum(&:subtotal).to_f

        # Build tax lines from hotel's custom taxes
        tax_lines = @quote.hotel.hotel_taxes.enabled.filter_map do |tax|
          next unless tax.applicable_for?(guest_country)
          tax.to_tax_line(rooms_subtotal: rooms_subtotal)
        end

        # Add SST if enabled (8% of room subtotal, all guests)
        if @quote.hotel.sst_enabled?
          tax_lines << {
            "name"   => "Service Tax (SST 8%)",
            "amount" => (rooms_subtotal * 0.08).round(2),
            "type"   => "sst"
          }
        end

        # Backward-compat: keep tourism_tax_amount/applied
        ttx = tax_lines.find { |t| t["name"].to_s.downcase.include?("tourism") }
        tourism_tax_amount = ttx ? ttx["amount"].to_f : @quote.hotel.tourism_tax_amount_for(guest_country)

        booking = Booking.new(
          booking_quote: @quote,
          hotel: @quote.hotel,
          guest_name: @payment_details[:guest_name], # From checkout form
          guest_email: @payment_details[:guest_email],
          guest_phone: @payment_details[:guest_phone],
          total_amount: @quote.total_amount,
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
          net_amount: net_amount,
          guest_gender: gender,
          guest_country: guest_country,
          guest_document_type: document_type,
          tourism_tax_amount: tourism_tax_amount,
          tourism_tax_applied: tourism_tax_amount.positive?,
          tax_lines: tax_lines,
          reservation_number: reservation_num,
          receipt_number: receipt_num
        )


        if booking.save
          # 3. Link Guest Profile
          guest_result = GuestArrival::CreateOrMatchGuest.new(
            name: @payment_details[:guest_name],
            email: @payment_details[:guest_email],
            phone: @payment_details[:guest_phone],
            government_id: @payment_details[:government_id],
            gender: gender,
            country: guest_country,
            document_type: document_type,
            marketing_consent: @payment_details[:marketing_consent],
            privacy_consent: @payment_details[:privacy_consent]
          ).call

          if guest_result.success?
            booking.booking_guests.create!(guest: guest_result.guest, is_primary: true)
          end

          # 4. Initialize Pre-checkin
          GuestArrival::StartPreCheckin.new(booking).call

          # 5. Create Booking Rooms
          @quote.booking_quote_items.each do |item|
            booking.booking_rooms.create!(
              room_type: item.room_type,
              quantity: item.quantity,
              subtotal: item.subtotal,
              room_type_snapshot: item.room_type_snapshot,
              nightly_rate_snapshot: item.nightly_rate_snapshot,
              occupancy_snapshot: item.occupancy_snapshot
            )
          end

          # 4. Finalize Quote status
          @quote.update!(status: "converted")

          # Record Audit Logs
          Bookings::RecordAuditLog.call(auditable: @quote, action_type: "convert")
          Bookings::RecordAuditLog.call(auditable: booking, action_type: "create")

          # 5. Trigger Webhooks
          Bookings::WebhookTriggerService.new(booking).trigger(:booking_confirmed)
          Notifications::Dispatcher.new(event: :booking_confirmed, booking: booking).call

          # 6. TODO: Trigger notifications (Phase 5 checklist)
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

    def existing_booking
      @existing_booking ||= Booking.find_by(booking_quote_id: @quote.id)
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
