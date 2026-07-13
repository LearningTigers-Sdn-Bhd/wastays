# frozen_string_literal: true

require "ostruct"

module Folios
  class PostEarlyCheckoutCharges
    include NightlyChargeCalculation

    def self.call(booking:, folio:, user:, departure_date:, original_check_out:, options: {})
      new(
        booking: booking,
        folio: folio,
        user: user,
        departure_date: departure_date,
        original_check_out: original_check_out,
        options: options
      ).call
    end

    def self.preview(booking:, departure_date:, original_check_out:)
      new(
        booking: booking,
        folio: nil,
        user: nil,
        departure_date: departure_date,
        original_check_out: original_check_out,
        options: {}
      ).preview
    end

    def self.pending_preview(booking:, folio:, departure_date:, original_check_out:)
      new(
        booking: booking,
        folio: folio,
        user: nil,
        departure_date: departure_date,
        original_check_out: original_check_out,
        options: {}
      ).pending_preview
    end

    def self.projected_checkout_balance(folio:, departure_date:, original_check_out:)
      actual_balance = folio.outstanding_balance
      pending = pending_preview(
        booking: folio.booking,
        folio: folio,
        departure_date: departure_date,
        original_check_out: original_check_out
      )
      actual_balance + pending.sum { |l| l[:amount].to_d }
    end

    def initialize(booking:, folio:, user:, departure_date:, original_check_out:, options: {})
      @booking = booking
      @folio = folio
      @user = user
      @departure_date = departure_date.to_date
      @original_check_out = original_check_out.to_date
      @options = options
    end

    def call
      return failure("Booking has no folio.") unless @folio

      transactions = []
      @folio.with_lock do
        @folio.reload
        preview.each do |line|
          next if line[:amount].to_d.zero?
          next if already_posted?(line[:key])

          result = Folios::InsertTransaction.new(
            booking_folio: @folio,
            amount: line[:amount],
            transaction_type: "charge",
            category: line[:category],
            user: @user,
            description: line[:description],
            posting_date: @departure_date,
            options: transaction_options(line)
          ).call

          return failure(result.error) unless result.success?

          transactions << result.transaction
        end
      end

      success(transactions)
    end

    def preview
      unused_nights.each_with_index.flat_map do |date, index|
        night_number = index + 1
        [ accommodation_line(date, night_number), *tax_lines(date, night_number) ].compact
      end
    end

    def pending_preview
      preview.reject { |line| @folio && already_posted?(line[:key]) }
    end

    private

    def unused_nights
      (@departure_date...@original_check_out).to_a
    end

    def accommodation_line(date, night_number)
      amount = @booking.booking_rooms.to_a.sum { |room| nightly_room_amount(room, date) }.to_d
      return if amount.zero?

      {
        amount: amount,
        category: "early_departure_charge",
        description: "Early checkout charge - Night #{night_number}",
        date: date,
        key: idempotency_key(date, "accommodation")
      }
    end

    def tax_lines(date, night_number)
      tax_postings_for(date).each_with_index.filter_map do |tax_line, index|
        amount = tax_line_amount(tax_line).to_d
        next if amount.zero?

        identity = tax_line_identity(tax_line, index)
        name = tax_line_name(tax_line)
        {
          amount: amount,
          category: "tax",
          description: "Early checkout tax - Night #{night_number} - #{name}",
          date: date,
          key: idempotency_key(date, "tax", identity),
          tax_line: tax_line
        }
      end
    end

    def nightly_room_amount(booking_room, date)
      snapshot = booking_room.nightly_rate_snapshot.to_h[date.iso8601]
      return snapshot["price"].to_d if snapshot.present?

      nightly_amount(booking_room.subtotal, date)
    end

    def tax_postings_for(date)
      postings = @booking.tax_posting_snapshot.to_h[date.iso8601]
      return postings if postings.present?

      booking_tax_lines.each_with_index.map do |tax_line, index|
        tax_line.to_h.merge(
          "amount" => nightly_amount(tax_line_amount(tax_line), date).to_s("F"),
          "tax_line_index" => index,
          "source" => tax_line["source"].presence || tax_line[:source].presence || "legacy_tax_lines"
        )
      end
    end

    def nightly_amount(total_amount, date)
      nights = (@original_check_out - @booking.check_in.to_date).to_i
      return 0.to_d unless nights.positive?

      per_night = (total_amount.to_d / nights).round(2)
      return per_night unless date == @original_check_out - 1.day

      total_amount.to_d - (per_night * (nights - 1))
    end

    def booking_tax_lines
      lines = Array(@booking.tax_lines)
      return lines if lines.any?
      return [] unless @booking.tourism_tax_amount.to_d.positive?

      [ { "name" => "Tourism Tax", "amount" => @booking.tourism_tax_amount, "type" => "tourism_tax" } ]
    end

    def idempotency_key(date, kind, identity = nil)
      ChargePostingKeys.early_checkout_charge_key(
        booking: @booking,
        date: date,
        charge_kind: kind,
        identity: identity
      )
    end

    def already_posted?(key)
      @folio.folio_transactions.where(voided_by_transaction_id: nil).where("metadata->>'early_checkout_charge_key' = ?", key).exists?
    end

    def transaction_options(line)
      metadata = {
        posting_source: "early_departure",
        stay_date: line[:date].iso8601,
        original_check_out: @original_check_out.iso8601,
        early_checkout_charge_key: line[:key]
      }
      metadata[:tax_line] = line[:tax_line] if line[:tax_line].present?

      options = @options.merge(metadata: (@options[:metadata] || {}).merge(metadata))

      if @booking.hotel.date_closed?(@departure_date) || @departure_date < @booking.hotel.current_business_date
        options[:override_night_audit] = true
        options[:correction_reason] ||= "early_departure_charge_on_closed_date"
        options[:correction_note] ||= "Automated posting of early departure charges on a closed business date."
      end

      options
    end

    def success(transactions)
      OpenStruct.new(success?: true, transactions: transactions)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
