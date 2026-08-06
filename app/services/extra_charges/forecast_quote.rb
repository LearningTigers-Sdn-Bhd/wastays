# frozen_string_literal: true

require "digest"

module ExtraCharges
  class ForecastQuote
    Result = ApplicationResult.define(
      :allowed_dates, :starts_on, :ends_on, :unit_rate, :configured_rate,
      :dates, :base_total, :tax_total, :grand_total, :fingerprint
    )

    def self.call(extra_charge:, folio:, booking:, starts_on: nil, ends_on: nil, unit_rate: nil, expected_fingerprint: nil)
      new(extra_charge:, folio:, booking:, starts_on:, ends_on:, unit_rate:, expected_fingerprint:).call
    end

    def initialize(extra_charge:, folio:, booking:, starts_on:, ends_on:, unit_rate:, expected_fingerprint:)
      @extra_charge = extra_charge
      @folio = folio
      @booking = booking
      @starts_on = parse_date(starts_on)
      @ends_on = parse_date(ends_on)
      @requested_unit_rate = unit_rate
      @expected_fingerprint = expected_fingerprint.to_s
    end

    def call
      return failure("Only fixed night-based extra charges can be scheduled.") unless @extra_charge.fixed? && @extra_charge.nightly?
      return failure("Extra charge is not available for this booking.") unless available?
      return failure("No remaining occupied nights are available for this charge.") if allowed_dates.empty?
      return failure("Select dates within the remaining stay.") if selected_dates.empty? || selected_dates.any? { |date| !allowed_dates.include?(date) }
      return failure("Unit rate must be greater than zero.") unless unit_rate.positive?
      if @requested_unit_rate.present? && !@extra_charge.allow_amount_override? && unit_rate != @extra_charge.rate_value.to_d
        return failure("This extra charge does not allow a rate override.")
      end

      result = build_result
      return result if @expected_fingerprint.blank? || @expected_fingerprint == result.fingerprint

      Result.failure(
        "Charge details changed. Review the refreshed dated breakdown before posting.",
        **result.to_h.except(:"success?", :error)
      )
    end

    private

    def available?
      @extra_charge.hotel_id == @booking.hotel_id && @folio.booking_id == @booking.id &&
        @folio.open? && @extra_charge.transaction_code.active?
    end

    def allowed_dates
      @allowed_dates ||= Bookings::ScheduledStay.stay_dates(
        hotel: @booking.hotel,
        check_in: @booking.check_in,
        check_out: @booking.check_out
      ).select { |date| date >= @booking.hotel.current_business_date }
    end

    def selected_dates
      @selected_dates ||= begin
        first = @starts_on || allowed_dates.first
        last = @ends_on || allowed_dates.last
        first && last && first <= last ? (first..last).to_a : []
      end
    end

    def unit_rate
      @unit_rate ||= if @requested_unit_rate.present? && @extra_charge.allow_amount_override?
        @requested_unit_rate.to_d
      else
        @extra_charge.rate_value.to_d
      end
    end

    def quantity
      @quantity ||= case @extra_charge.charging_unit
      when "per_room_night" then [ @booking.booking_rooms.count, 1 ].max
      when "per_person_night" then [ @booking.adults.to_i + @booking.children.to_i, 1 ].max
      else 1
      end
    end

    def build_result
      rows = selected_dates.map { |date| row_for(date) }
      base_total = money(rows.sum { |row| row[:base_amount] })
      tax_total = money(rows.sum { |row| row[:tax_total] })
      fingerprint = Digest::SHA256.hexdigest(fingerprint_payload(rows).to_json)

      Result.success(
        allowed_dates: allowed_dates,
        starts_on: selected_dates.first,
        ends_on: selected_dates.last,
        unit_rate: unit_rate,
        configured_rate: @extra_charge.rate_value.to_d,
        dates: rows,
        base_total: base_total,
        tax_total: tax_total,
        grand_total: money(base_total + tax_total),
        fingerprint: fingerprint
      )
    end

    def row_for(date)
      base_amount = money(unit_rate * quantity)
      base_folio = resolved_base_folio(date)
      taxes = effective_tax_rules.filter_map.with_index do |rule, index|
        amount = money(rule.compute(base_amount))
        next if amount.zero?

        code = rule.posting_transaction_code
        target = tax_target_folio(code, base_folio, date)
        {
          line_key: "tax:#{rule.tax_rule_key}:#{index}",
          name: rule.display_name,
          amount: amount,
          rate_type: rule.rate_type,
          rate: rule.amount.to_d,
          tax_rule_key: rule.tax_rule_key,
          transaction_code_id: code&.id,
          transaction_code_code: code&.code,
          transaction_code_name: code&.name,
          target_folio_id: target.id,
          target_folio_label: target.display_option_label
        }
      end

      {
        date: date,
        quantity: quantity,
        unit_rate: unit_rate,
        base_amount: base_amount,
        base_target_folio_id: base_folio.id,
        base_target_folio_label: base_folio.display_option_label,
        taxes: taxes,
        tax_total: money(taxes.sum { |tax| tax[:amount] }),
        total: money(base_amount + taxes.sum { |tax| tax[:amount] }),
        posting_state: "upcoming"
      }
    end

    def resolved_base_folio(date)
      route = Folios::Routing::ResolveTargetFolio.call(
        booking: @booking,
        transaction_code: @extra_charge.transaction_code,
        posting_date: date
      )
      raise route.error unless route.success?

      route.route_source == "primary_folio" ? @folio : route.folio
    end

    def tax_target_folio(transaction_code, base_folio, date)
      return base_folio if transaction_code.blank?

      rule = @booking.folio_routing_rules.active
        .where(transaction_code: transaction_code)
        .where("effective_from IS NULL OR effective_from <= ?", date)
        .where("effective_until IS NULL OR effective_until >= ?", date)
        .includes(:target_folio)
        .first
      rule&.target_folio || base_folio
    end

    def effective_tax_rules
      @effective_tax_rules ||= Folios::Routing::EffectiveTaxRules.call(
        booking: @booking,
        transaction_code: @extra_charge.transaction_code
      ).select(&:enabled_for_posting?)
    end

    def fingerprint_payload(rows)
      {
        extra_charge_id: @extra_charge.id,
        transaction_code_id: @extra_charge.transaction_code_id,
        charging_unit: @extra_charge.charging_unit,
        configured_rate: @extra_charge.rate_value.to_d.to_s("F"),
        unit_rate: unit_rate.to_s("F"),
        rows: rows
      }
    end

    def failure(error)
      Result.failure(error, allowed_dates: allowed_dates)
    end

    def parse_date(value)
      value.present? ? value.to_date : nil
    rescue ArgumentError, NoMethodError
      nil
    end

    def money(value) = value.to_d.round(2)
  end
end
