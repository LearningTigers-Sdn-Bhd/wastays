# frozen_string_literal: true

module Bookings
  class BuildRoomChargeCorrectionSnapshot
    Snapshot = Data.define(:room_attributes, :booking_attributes, :nights, :charge_keys)

    def self.room_tax?(posting, room_revenue_code_id: nil)
      posting["type"] != "tourism_tax" && posting["primary_tax_key"] != "tourism_tax" &&
        posting["basis"] == "nightly_room_charge" &&
        (!room_revenue_code_id || posting["source_transaction_code_id"].blank? || posting["source_transaction_code_id"].to_i == room_revenue_code_id)
    end

    def self.charge_keys_for(booking:, dates: nil)
      room = booking.booking_rooms.sole
      code_id = booking.hotel.transaction_codes.find_by!(system_key: "room_revenue").id
      dates ||= ScheduledStay.stay_dates(hotel: booking.hotel, check_in: booking.check_in, check_out: booking.check_out)
      dates.flat_map do |date|
        keys = [ Folios::Charges::ChargePostingKeys.nightly_charge_key(booking: booking, date: date, charge_kind: "accommodation", identity: room.id) ]
        Array(booking.tax_posting_snapshot.to_h[date.iso8601]).each_with_index do |posting, index|
          next unless room_tax?(posting, room_revenue_code_id: code_id)

          identity = posting["posting_identity"].presence || posting["type"].presence || posting["name"].to_s.parameterize.presence || "tax"
          keys << Folios::Charges::ChargePostingKeys.nightly_charge_key(booking: booking, date: date, charge_kind: "tax", identity: "#{identity}:#{index}")
        end
        keys
      end
    end

    # nightly_amounts maps ISO stay dates to tax-inclusive amounts. A blank
    # amount, or one equal to the recorded amount, leaves that night untouched.
    def initialize(booking:, nightly_amounts:)
      @booking = booking
      @room = booking.booking_rooms.sole
      @room_revenue_code_id = booking.hotel.transaction_codes.find_by!(system_key: "room_revenue").id
      @amounts = nightly_amounts.to_h.transform_keys(&:to_s).transform_values { |value| value.to_s.strip }
        .reject { |_date, value| value.empty? }.transform_values { |value| parse_amount(value) }
    end

    # Recorded tax-inclusive amount for each billable night, for the entry form.
    def current_nights
      taxes = @booking.tax_posting_snapshot.to_h
      rates = @room.nightly_rate_snapshot.to_h
      stay_dates.map do |date|
        key = date.iso8601
        original = rate_for(rates, key)
        { date: key, current_amount: gross_amount(original, Array(taxes[key]).select { |posting| room_tax?(posting) }) }
      end
    end

    def call
      dates = stay_dates
      raise ArgumentError, "This booking has no billable nights." if dates.empty?
      unknown = @amounts.keys - dates.map(&:iso8601)
      raise ArgumentError, "Enter amounts only for the nights of this stay." if unknown.any?

      rates = @room.nightly_rate_snapshot.to_h.deep_dup
      taxes = @booking.tax_posting_snapshot.to_h.deep_dup
      validate_tax_totals!(taxes)
      if taxes.empty? && Booking.non_tourism_tax_total_for(@booking.tax_lines).positive?
        raise ArgumentError, "Recorded nightly tax rules are missing. Use a separate folio correction."
      end

      nights = dates.filter_map do |date|
        key = date.iso8601
        original = rate_for(rates, key)

        postings = Array(taxes[key])
        room_taxes = postings.select { |posting| room_tax?(posting) }
        validate_rules!(room_taxes)
        # A legacy tax without its calculation basis cannot safely be classified.
        if postings.any? { |posting| posting["type"] != "tourism_tax" && posting["primary_tax_key"] != "tourism_tax" && posting["basis"].blank? }
          raise ArgumentError, "Recorded nightly tax rules are incomplete for #{key}. Use a separate folio correction."
        end

        old_gross = gross_amount(original, room_taxes)
        amount = @amounts[key]
        next if amount.nil? || amount == old_gross

        net = solve_room_amount(room_taxes, amount)
        updated_taxes = postings.map do |posting|
          next posting unless room_tax?(posting)

          posting.merge("basis_amount" => net.to_s("F"), "amount" => tax_amount(posting, net).to_s("F"))
        end
        rates[key] = original.merge("price" => net.to_s("F"), "source" => "room_charge_correction")
        rates[key]["posting_price"] = net.to_s("F") if original.key?("posting_price")
        taxes[key] = updated_taxes if taxes.key?(key)
        {
          date: key, current_amount: old_gross.to_s("F"), corrected_amount: amount.to_s("F"),
          difference: (amount - old_gross).to_s("F"), room_amount: net.to_s("F"),
          taxes: room_taxes.zip(updated_taxes.select { |posting| room_tax?(posting) }).map do |before, after|
            { name: before["name"], current_amount: before["amount"], corrected_amount: after["amount"] }
          end
        }
      end
      raise ArgumentError, "The corrected room charges are unchanged." if nights.empty?

      room_total = dates.sum { |date| rates.fetch(date.iso8601).fetch("price").to_d }
      tax_lines = corrected_tax_lines(taxes)
      Snapshot.new(
        room_attributes: { nightly_rate_snapshot: rates, subtotal: room_total },
        booking_attributes: { tax_posting_snapshot: taxes, tax_lines: tax_lines,
          total_amount: room_total + Booking.non_tourism_tax_total_for(tax_lines), manual_rate_override: room_total },
        nights: nights,
        charge_keys: self.class.charge_keys_for(booking: @booking, dates: nights.map { |night| Date.iso8601(night[:date]) })
      )
    end

    private

    def stay_dates
      ScheduledStay.stay_dates(hotel: @booking.hotel, check_in: @booking.check_in, check_out: @booking.check_out)
    end

    def parse_amount(value)
      amount = BigDecimal(value)
      raise ArgumentError unless amount.finite? && amount >= 0 && amount == amount.round(2)

      amount
    rescue ArgumentError
      raise ArgumentError, "Enter a nonnegative nightly amount with at most two decimal places."
    end

    def rate_for(rates, key)
      original = rates[key]
      raise ArgumentError, "Recorded room rate is missing for #{key}." unless original.is_a?(Hash) && original["price"].present?

      original
    end

    def gross_amount(original, room_taxes)
      (original["posting_price"].presence || original["price"]).to_d + room_taxes.sum { |posting| posting["amount"].to_d }
    end

    def room_tax?(posting)
      self.class.room_tax?(posting, room_revenue_code_id: @room_revenue_code_id)
    end

    def validate_tax_totals!(taxes)
      identities = taxes.values.flatten.map { |posting| posting.values_at("name", "type", "source") }
      missing = @booking.tax_lines.any? do |line|
        line["type"] != "tourism_tax" && line["amount"].to_d.positive? && !identities.include?(line.values_at("name", "type", "source"))
      end
      raise ArgumentError, "Recorded nightly tax rules are missing. Use a separate folio correction." if missing

      groups = taxes.values.flatten.select { |posting| room_tax?(posting) }.group_by { |posting| posting.values_at("name", "type", "source") }
      groups.each do |identity, postings|
        lines = @booking.tax_lines.select { |line| line.values_at("name", "type", "source") == identity }
        unless lines.one? && lines.sole["amount"].to_d == postings.sum { |posting| posting["amount"].to_d }
          raise ArgumentError, "Recorded room tax totals do not match their nightly rules. Use a separate folio correction."
        end
      end
    end

    def validate_rules!(postings)
      postings.each do |posting|
        rate = BigDecimal(posting["rate"].to_s)
        raise ArgumentError unless rate.finite? && rate >= 0 && posting["rate_type"].in?(%w[percentage flat])
      rescue ArgumentError
        raise ArgumentError, "Recorded nightly tax rules are incomplete. Use a separate folio correction."
      end
    end

    def tax_amount(posting, net)
      rate = posting.fetch("rate").to_d
      posting.fetch("rate_type") == "percentage" ? (net * rate / 100).round(2) : rate
    end

    def solve_room_amount(postings, amount)
      flat = postings.select { |posting| posting["rate_type"] == "flat" }.sum { |posting| posting["rate"].to_d }
      percentage = postings.select { |posting| posting["rate_type"] == "percentage" }.sum { |posting| posting["rate"].to_d }
      candidate = ((amount - flat) / (1 + percentage / 100)).round(2)
      radius = postings.length + 2
      offsets = [ 0 ] + (1..radius).flat_map { |offset| [ offset, -offset ] }
      net = offsets.map { |offset| candidate + offset.to_d / 100 }.find do |value|
        value >= 0 && value + postings.sum { |posting| tax_amount(posting, value) } == amount
      end
      raise ArgumentError, "This nightly amount cannot match the recorded room tax rules. Enter another amount." unless net

      net
    end

    def corrected_tax_lines(taxes)
      original = @booking.tax_posting_snapshot.to_h.values.flatten.select { |posting| room_tax?(posting) }
      corrected = taxes.values.flatten.select { |posting| room_tax?(posting) }
      @booking.tax_lines.map do |line|
        matches = ->(posting) { posting.values_at("name", "type", "source") == line.values_at("name", "type", "source") }
        before = original.select(&matches)
        next line.deep_dup if before.empty?

        difference = corrected.select(&matches).sum { |posting| posting["amount"].to_d } - before.sum { |posting| posting["amount"].to_d }
        line.merge("amount" => (line["amount"].to_d + difference).to_s("F"))
      end
    end
  end
end
