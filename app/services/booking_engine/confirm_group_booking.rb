# frozen_string_literal: true

require "ostruct"

module BookingEngine
  class ConfirmGroupBooking
    def self.call(quote:, payment_details:)
      new(quote: quote, payment_details: payment_details).call
    end

    def initialize(quote:, payment_details:)
      @quote = quote
      @payment_details = payment_details.with_indifferent_access
    end

    def call
      existing = @quote.bookings.includes(:group_booking).first if @quote.respond_to?(:bookings)
      return success(existing.group_booking, existing.group_booking.bookings.to_a) if existing&.group_booking

      group = nil
      bookings = []
      GroupBooking.transaction(requires_new: true) do
        guest = create_or_match_guest!
        group = create_group!(guest)
        units.each_with_index do |item, index|
          booking = create_child_booking!(group, guest, item, index)
          bookings << booking
        end
        receive_and_allocate_payment!(group, bookings) if payment_received?
        @quote.update!(status: "converted", special_requests: @payment_details[:special_requests])
        Bookings::RecordAuditLog.call!(auditable: @quote, action_type: "convert", source: "guest")
      end

      bookings.each do |booking|
        Bookings::WebhookTriggerService.new(booking).trigger(:booking_confirmed)
        Notifications::Dispatcher.new(event: :booking_confirmed, booking: booking).call
      end
      success(group, bookings)
    rescue StandardError => e
      OpenStruct.new(success?: false, message: "Group confirmation failed: #{e.message}", group_booking: nil, bookings: [])
    end

    private

    def units
      @units ||= @quote.booking_quote_items.includes(:room_type).flat_map do |item|
        Array.new(item.quantity) { item }
      end
    end

    def create_or_match_guest!
      result = GuestArrival::CreateOrMatchGuest.new(
        name: @payment_details[:guest_name],
        email: @payment_details[:guest_email],
        phone: @payment_details[:guest_phone],
        government_id: @payment_details[:guest_government_id],
        gender: normalized_gender,
        country: normalized_country,
        document_type: normalized_document_type,
        date_of_birth: @payment_details[:date_of_birth],
        marketing_consent: @payment_details[:marketing_consent],
        privacy_consent: @payment_details[:privacy_consent]
      ).call
      raise result.error || "Guest could not be created." unless result.success?

      result.guest
    end

    def create_group!(guest)
      @quote.hotel.group_bookings.create!(
        organizer_guest: guest,
        name: @payment_details[:group_name].presence || "#{@payment_details[:guest_name]} group",
        source: "booking_quote",
        external_reference: @quote.token,
        default_check_in: @quote.check_in,
        default_check_out: @quote.check_out,
        metadata: { booking_quote_id: @quote.id }
      )
    end

    def create_child_booking!(group, guest, item, index)
      snapshot = financial_snapshot_for(item)
      tourism_tax = snapshot.tax_lines.find { |tax| tax["type"].to_s == "tourism_tax" }
      total = snapshot.room_total + Booking.non_tourism_tax_total_for(snapshot.tax_lines)
      margin_rate = @quote.hotel.effective_margin_rate
      margin_amount = (total * (margin_rate / 100.0)).round(2)

      booking = @quote.hotel.bookings.create!(
        booking_quote: @quote,
        group_booking: group,
        group_position: index + 1,
        guest_name: @payment_details[:guest_name],
        guest_email: @payment_details[:guest_email],
        guest_phone: @payment_details[:guest_phone],
        special_requests: @payment_details[:special_requests],
        total_amount: total,
        currency: @quote.currency,
        check_in: @quote.check_in,
        check_out: @quote.check_out,
        adults: adults_for(index),
        children: children_for(index),
        hotel_snapshot: @quote.hotel_snapshot,
        cancellation_policy_snapshot: @quote.cancellation_policy_snapshot,
        status: "confirmed",
        payment_status: payment_received? ? "captured" : "pending",
        source: "direct",
        margin_rate: margin_rate,
        margin_amount: margin_amount,
        net_amount: total - margin_amount,
        guest_gender: normalized_gender,
        guest_country: normalized_country,
        guest_document_type: normalized_document_type,
        tourism_tax_amount: tourism_tax&.fetch("amount", 0).to_d,
        tourism_tax_applied: tourism_tax.present?,
        tax_lines: snapshot.tax_lines,
        tax_posting_snapshot: snapshot.tax_posting_snapshot,
        reservation_number: HotelCounter.increment!(hotel: @quote.hotel, type: "reservation"),
        receipt_number: HotelCounter.increment!(hotel: @quote.hotel, type: "receipt")
      )
      booking.booking_rooms.create!(
        room_type: item.room_type,
        subtotal: item.subtotal / item.quantity,
        room_type_snapshot: item.room_type_snapshot,
        nightly_rate_snapshot: normalized_snapshot(item.nightly_rate_snapshot),
        occupancy_snapshot: item.occupancy_snapshot
      )
      booking.booking_guests.create!(guest: guest, is_primary: true)
      GuestArrival::StartPreCheckin.new(booking).call
      Folios::Lifecycle::InitializeForBooking.call(
        booking: booking,
        user: nil,
        options: { system_folio_initialization: true, posting_source: "group_booking_confirmation" },
        lock: false
      )
      Bookings::RecordAuditLog.call!(auditable: booking, action_type: "create", source: "guest")
      booking
    end

    def financial_snapshot_for(item)
      Bookings::BuildFinancialSnapshot.new(
        hotel: @quote.hotel,
        check_in: @quote.check_in,
        check_out: @quote.check_out,
        guest_country: normalized_country,
        room_items: [ { quantity: 1, nightly_rate_snapshot: item.nightly_rate_snapshot } ]
      ).call
    end

    def receive_and_allocate_payment!(group, bookings)
      result = Deposits::Record.call(
        owner: group,
        kind: "prepayment",
        amount: bookings.sum(&:total_amount),
        currency: @quote.currency,
        payment_method: @payment_details[:payment_method].presence || "gateway",
        external_reference: @payment_details[:transaction_id].presence || @payment_details[:external_reference],
        metadata: { booking_quote_id: @quote.id }
      )
      raise result.error unless result.success?

      manual_amounts = bookings.to_h { |booking| [ booking.booking_folio.id.to_s, booking.total_amount ] }
      allocation = Deposits::ApplyAcrossFolios.call(
        deposit: result.deposit,
        folios: bookings.map(&:booking_folio),
        amount: bookings.sum(&:total_amount),
        strategy: "manual",
        manual_amounts: manual_amounts,
        operation_key: "group-confirmation:#{group.id}:payment"
      )
      raise allocation.error unless allocation.success?
    end

    def payment_received?
      true
    end

    def normalized_snapshot(snapshot)
      snapshot.to_h.transform_keys(&:to_s).transform_values do |value|
        value.respond_to?(:to_h) ? value.to_h.transform_keys(&:to_s) : { "price" => value }
      end
    end

    def adults_for(index)
      quotient, remainder = @quote.adults.divmod(units.size)
      quotient + (index < remainder ? 1 : 0)
    end

    def children_for(index)
      quotient, remainder = @quote.children.to_i.divmod(units.size)
      quotient + (index < remainder ? 1 : 0)
    end

    def normalized_gender
      @normalized_gender ||= @payment_details[:gender]&.downcase&.strip
    end

    def normalized_document_type
      @normalized_document_type ||= @payment_details[:document_type]&.downcase&.strip
    end

    def normalized_country
      @normalized_country ||= begin
        value = @payment_details[:country]
        country = ISO3166::Country.find_country_by_any_name(value.to_s.strip) if value.present?
        country&.iso_short_name || value.to_s.split.map(&:capitalize).join(" ").presence
      rescue StandardError
        value.to_s.split.map(&:capitalize).join(" ").presence
      end
    end

    def success(group, bookings)
      OpenStruct.new(success?: true, booking: bookings.first, bookings: bookings, group_booking: group)
    end
  end
end
