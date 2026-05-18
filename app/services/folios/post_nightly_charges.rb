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
        .where("check_in <= ? AND check_out > ?", @business_date, @business_date)
    end

    def post_accommodation_charges(booking)
      booking.booking_rooms.each do |booking_room|
        amount = nightly_amount(booking_room.subtotal, booking, @business_date)
        next if amount.zero?

        insert_transaction!(
          booking: booking,
          amount: amount,
          category: "accommodation",
          description: "Room Charge - #{@business_date}",
          metadata: nightly_metadata(booking, "accommodation", booking_room.id)
        )
      end
    end

    def post_tax_charges(booking)
      tax_lines_for(booking).each_with_index do |tax_line, index|
        amount = nightly_amount(tax_line_amount(tax_line), booking, @business_date)
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
      return if already_posted?(booking.booking_folio, metadata[:nightly_charge_key])

      result = Folios::InsertTransaction.new(
        booking_folio: booking.booking_folio,
        amount: amount,
        transaction_type: :charge,
        category: category,
        user: @user,
        description: description,
        posting_date: @business_date,
        options: @options.merge(metadata: metadata)
      ).call

      return if result.success? || already_posted?(booking.booking_folio, metadata[:nightly_charge_key])

      raise "Failed to post nightly folio charge: #{result.error}"
    end

    def already_posted?(folio, nightly_charge_key)
      folio.folio_transactions.charge.where("metadata->>'nightly_charge_key' = ?", nightly_charge_key).exists?
    end

    def nightly_metadata(booking, charge_kind, identity)
      {
        posting_source: "night_audit",
        night_audit_id: @night_audit.id,
        stay_date: @business_date.iso8601,
        booking_id: booking.id,
        charge_kind: charge_kind,
        nightly_charge_key: nightly_charge_key(booking, charge_kind, identity)
      }
    end

    def nightly_charge_key(booking, charge_kind, identity)
      [ booking.id, @business_date.iso8601, charge_kind, identity ].join(":")
    end
  end
end
