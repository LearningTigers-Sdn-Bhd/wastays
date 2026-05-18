# frozen_string_literal: true

module Folios
  class PostNightlyCharges
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
        amount = nightly_amount(booking_room.subtotal, booking)
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
        amount = nightly_amount(tax_line_amount(tax_line), booking)
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

    def nightly_amount(total_amount, booking)
      nights = (booking.check_out.to_date - booking.check_in.to_date).to_i
      return 0.to_d unless nights.positive?

      per_night = (total_amount.to_d / nights).round(2)
      return per_night unless @business_date == booking.check_out.to_date - 1.day

      total_amount.to_d - (per_night * (nights - 1))
    end

    def tax_lines_for(booking)
      tax_lines = Array(booking.tax_lines)
      return tax_lines if tax_lines.any?

      return [] unless booking.tourism_tax_amount.to_d.positive?

      [ { "name" => "Tourism Tax", "amount" => booking.tourism_tax_amount, "type" => "tourism_tax" } ]
    end

    def tax_line_amount(tax_line)
      (tax_line["amount"].presence || tax_line[:amount]).to_d
    end

    def tax_line_name(tax_line)
      tax_line["name"].presence || tax_line[:name].presence || "Tax"
    end

    def tax_line_identity(tax_line, index)
      identity = tax_line["type"].presence || tax_line[:type].presence || tax_line_name(tax_line).parameterize.presence || "tax"
      "#{identity}:#{index}"
    end
  end
end
