# frozen_string_literal: true

module Folios
  class PostNightlyCharges
    include NightlyChargeCalculation

    def self.call(night_audit:, user:, options: {})
      new(night_audit: night_audit, user: user, options: options).call
    end

    def initialize(night_audit:, user:, options: {})
      @night_audit = night_audit
      @hotel = night_audit.hotel
      @business_date = night_audit.business_date.to_date
      @user = user
      @options = options
    end

    def call
      bookings_to_post.each do |booking|
        next unless booking.booking_folio

        booking.booking_folio.with_lock do
          post_accommodation_charges(booking)
          post_tax_charges(booking)
        end
      end
    end

    private

    def bookings_to_post
      @bookings_to_post ||= @hotel.bookings
        .includes(:booking_rooms, :booking_folio)
        .where(status: "checked_in")
        .where("check_in <= ? AND check_out > ?", @business_date.end_of_day, @business_date.beginning_of_day)
    end

    def post_accommodation_charges(booking)
      booking.booking_rooms.each do |booking_room|
        amount = nightly_room_amount(booking_room, @business_date)
        next if amount.zero?

        insert_transaction!(
          booking: booking,
          amount: amount,
          category: "accommodation",
          description: "Room Charge - #{@business_date}",
          metadata: nightly_metadata(booking, "accommodation", booking_room.id).merge(
            rate_source: nightly_rate_snapshot_for(booking_room, @business_date).present? ? "nightly_rate_snapshot" : "legacy_subtotal_average",
            nightly_rate_snapshot: nightly_rate_snapshot_for(booking_room, @business_date)
          )
        )
      end
    end

    def post_tax_charges(booking)
      tax_postings_for(booking, @business_date).each_with_index do |tax_line, index|
        amount = tax_line_amount(tax_line)
        next if amount.zero?

        tax_identity = tax_line_identity(tax_line, index)
        insert_transaction!(
          booking: booking,
          amount: amount,
          category: "tax",
          description: "Tax: #{tax_line_name(tax_line)} - #{@business_date}",
          metadata: nightly_metadata(booking, "tax", tax_identity).merge(tax_line: tax_line)
        )
      end
    end

    def insert_transaction!(booking:, amount:, category:, description:, metadata:)
      existing_transaction = posted_transaction(booking.booking_folio, metadata[:nightly_charge_key])
      if existing_transaction
        actualize_forecast!(booking, existing_transaction, metadata)
        return
      end

      result = Folios::InsertTransaction.new(
        booking_folio: booking.booking_folio,
        amount: amount,
        transaction_type: :charge,
        category: category,
        user: @user,
        description: description,
        posting_date: @business_date,
        options: @options.merge(posting_source: "night_audit", metadata: metadata)
      ).call

      if result.success?
        actualize_forecast!(booking, result.transaction, metadata)
        return
      end

      existing_transaction = posted_transaction(booking.booking_folio, metadata[:nightly_charge_key])
      if existing_transaction
        actualize_forecast!(booking, existing_transaction, metadata)
        return
      end

      raise "Failed to post nightly folio charge: #{result.error}"
    end

    def posted_transaction(folio, nightly_charge_key)
      folio.folio_transactions.charge.where(voided_by_transaction_id: nil).find_by("metadata->>'nightly_charge_key' = ?", nightly_charge_key)
    end

    def actualize_forecast!(booking, transaction, metadata)
      forecast = booking.booking_folio.folio_forecasted_charges
        .forecast
        .find_by(stay_date: @business_date, charge_kind: metadata[:charge_kind], identity: metadata[:forecast_identity])

      forecast&.actualize!(transaction: transaction)
    end

    def nightly_metadata(booking, charge_kind, identity)
      {
        posting_source: "night_audit",
        night_audit_id: @night_audit.id,
        stay_date: @business_date.iso8601,
        booking_id: booking.id,
        charge_kind: charge_kind,
        forecast_identity: identity.to_s,
        nightly_charge_key: nightly_charge_key(booking, charge_kind, identity)
      }
    end

    def nightly_charge_key(booking, charge_kind, identity)
      ChargePostingKeys.nightly_charge_key(
        booking: booking,
        date: @business_date,
        charge_kind: charge_kind,
        identity: identity
      )
    end
  end
end
