# frozen_string_literal: true

require "ostruct"

module Bookings
  class BuildFinancialSnapshot
    def initialize(hotel:, check_in:, check_out:, guest_country:, room_type: nil, rate_plan: nil, quantity: 1, manual_total_amount: nil, nightly_rate_snapshot: nil, room_items: nil, corporate_rate: false, rate_tier: :standard)
      @hotel = hotel
      @check_in = check_in.to_date
      @check_out = check_out.to_date
      @guest_country = guest_country
      @room_type = room_type
      @rate_plan = rate_plan
      @quantity = quantity.to_i
      @manual_total_amount = manual_total_amount.presence&.to_d
      @nightly_rate_snapshot = nightly_rate_snapshot
      @room_items = room_items
      @corporate_rate = corporate_rate
      @rate_tier = rate_tier&.to_sym || :standard
    end

    def call
      rooms = normalized_room_items
      tax_posting_snapshot = build_tax_posting_snapshot(rooms)
      tax_lines = summarize_tax_lines(tax_posting_snapshot)

      OpenStruct.new(
        room_total: rooms.sum { |room| room[:total_amount] }.round(2),
        nightly_rate_snapshot: rooms.first&.fetch(:nightly_rate_snapshot, {}) || {},
        tax_total: tax_lines.sum { |line| line["amount"].to_d }.round(2),
        tax_lines: tax_lines,
        tax_posting_snapshot: tax_posting_snapshot
      )
    end

    private

    def stay_dates
      @stay_dates ||= (@check_in...@check_out).to_a
    end

    def normalized_room_items
      return Array(@room_items).map { |item| normalize_existing_room_item(item) } if @room_items.present?
      return [ build_manual_override_room_item ] if @manual_total_amount.present?

      [ build_room_rate_item ]
    end

    def normalize_existing_room_item(item)
      snapshot = normalize_snapshot(item.fetch(:nightly_rate_snapshot))
      quantity = item.fetch(:quantity, 1).to_i
      total = stay_dates.sum { |date| snapshot.dig(date.iso8601, "price").to_d * quantity }

      {
        quantity: quantity,
        total_amount: total,
        nightly_rate_snapshot: snapshot
      }
    end

    def build_room_rate_item
      raise ArgumentError, "Room type is required to build a rate snapshot." if @room_type.blank?

      currency = @rate_plan&.currency.presence || @hotel.default_currency.presence || "MYR"
      all_eligible_rates = @room_type.room_rates.where(date: stay_dates, currency: currency)
      rates_by_plan_and_date = all_eligible_rates.group_by(&:rate_plan_id)

      plans_to_try = [ @rate_plan, @room_type.rate_plans.first, nil ].uniq
      plan_ids_to_try = plans_to_try.map { |p| p.respond_to?(:id) ? p.id : p }

      snapshot = stay_dates.index_with do |date|
        rate = nil
        plan_ids_to_try.each do |pid|
          rate = rates_by_plan_and_date[pid]&.find { |r| r.date == date }
          break if rate
        end

        if rate.present?
          tier_kind = @rate_tier != :standard ? @rate_tier : rate.rate_plan&.special_tier_kind

          price = case tier_kind
          when :walk_in then rate.walk_in_price
          when :corporate then rate.corporate_price
          when :ota then rate.ota_price
          else
            @corporate_rate ? rate.corporate_price : nil
          end
          price ||= rate.price

          rate.as_json.merge(
            "room_rate_id" => rate.id,
            "source" => "room_rate",
            "price" => price.to_d.to_s("F"),
            "currency" => rate.currency
          )
        else
          {
            "date" => date.iso8601,
            "price" => @room_type.base_price.to_d.to_s("F"),
            "currency" => currency,
            "rate_plan_id" => @rate_plan&.id,
            "room_type_id" => @room_type.id,
            "source" => "base_price_fallback"
          }
        end
      end.transform_keys(&:iso8601)

      total = stay_dates.sum { |date| snapshot.dig(date.iso8601, "price").to_d * @quantity }

      {
        quantity: @quantity,
        total_amount: total,
        nightly_rate_snapshot: snapshot
      }
    end

    def build_manual_override_room_item
      nights = stay_dates.length
      raise ArgumentError, "Check-out date must be after check-in date." unless nights.positive?

      per_night = (@manual_total_amount / nights).round(2)
      snapshot = {}

      stay_dates.each_with_index do |date, index|
        amount = index == nights - 1 ? @manual_total_amount - (per_night * (nights - 1)) : per_night
        snapshot[date.iso8601] = {
          "date" => date.iso8601,
          "price" => amount.to_d.to_s("F"),
          "currency" => @hotel.default_currency.presence || "MYR",
          "rate_plan_id" => @rate_plan&.id,
          "room_type_id" => @room_type&.id,
          "source" => "manual_override"
        }
      end

      {
        quantity: 1,
        total_amount: @manual_total_amount,
        nightly_rate_snapshot: snapshot
      }
    end

    def normalize_snapshot(snapshot)
      snapshot.to_h.transform_keys(&:to_s).transform_values do |value|
        if value.respond_to?(:to_h)
          value.to_h.transform_keys(&:to_s)
        else
          { "price" => value }
        end
      end
    end

    def build_tax_posting_snapshot(rooms)
      build_room_transaction_code_tax_snapshot(rooms)
    end

    def build_room_transaction_code_tax_snapshot(rooms)
      snapshot = Hash.new { |hash, key| hash[key] = [] }
      rules = room_revenue_tax_rules
      return {} if rules.empty?

      rooms.each do |room|
        stay_dates.each do |date|
          date_key = date.iso8601
          basis_amount = room[:nightly_rate_snapshot].dig(date_key, "price").to_d * room[:quantity]
          next unless basis_amount.positive?

          rules.each do |rule|
            posting = room_transaction_code_tax_posting_for(rule, date, basis_amount, room[:quantity])
            snapshot[date_key] << posting if posting.present?
          end
        end
      end

      snapshot.transform_values { |items| items.map { |item| stringify_amounts(item) } }
    end

    def room_revenue_tax_rules
      return [] unless room_revenue_transaction_code&.active? && room_revenue_transaction_code.is_taxable?

      room_revenue_transaction_code.transaction_code_taxes.includes(:hotel_tax).select do |rule|
        room_transaction_code_tax_enabled?(rule)
      end
    end

    def room_revenue_transaction_code
      @room_revenue_transaction_code ||= begin
        Financials::EnsureDefaultTransactionCodes.call(@hotel)
        @hotel.transaction_codes.find_by(system_key: "room_revenue")
      end
    end

    def room_transaction_code_tax_enabled?(rule)
      if rule.hotel_tax.present?
        rule.hotel_tax.enabled? && rule.hotel_tax.applicable_for?(@guest_country)
      elsif rule.primary_tax_key == "sst_tax"
        @hotel.sst_enabled?
      elsif rule.primary_tax_key == "tourism_tax"
        @hotel.tourism_tax_amount_for(@guest_country).to_d.positive?
      else
        false
      end
    end

    def room_transaction_code_tax_posting_for(rule, date, basis_amount, quantity)
      amount = room_transaction_code_tax_amount(rule, basis_amount, quantity)
      return if amount.zero?

      transaction_code = rule.posting_transaction_code

      {
        "tax_id" => rule.hotel_tax_id,
        "primary_tax_key" => rule.primary_tax_key,
        "name" => rule.display_name,
        "type" => rule.tax_line_type,
        "transaction_code_id" => transaction_code&.id,
        "transaction_code_system_key" => transaction_code&.system_key,
        "transaction_code_code" => transaction_code&.code,
        "rate_type" => rule.rate_type,
        "rate" => room_transaction_code_tax_rate(rule),
        "basis" => room_transaction_code_tax_basis(rule),
        "basis_amount" => room_transaction_code_tax_basis_amount(rule, basis_amount, quantity),
        "amount" => amount,
        "currency" => @hotel.default_currency.presence || "MYR",
        "posting_schedule" => "nightly",
        "stay_date" => date.iso8601,
        "guest_country" => @guest_country,
        "foreign_guests_only" => rule.hotel_tax&.foreign_guests_only,
        "source" => "transaction_code_tax_rule",
        "source_transaction_code_id" => room_revenue_transaction_code.id
      }.compact
    end

    def room_transaction_code_tax_amount(rule, basis_amount, quantity)
      return @hotel.tourism_tax_amount_for(@guest_country).to_d * quantity.to_i if rule.primary_tax_key == "tourism_tax"

      rule.compute(basis_amount)
    end

    def room_transaction_code_tax_rate(rule)
      return @hotel.tourism_tax_amount_for(@guest_country).to_d if rule.primary_tax_key == "tourism_tax"

      rule.amount
    end

    def room_transaction_code_tax_basis(rule)
      rule.primary_tax_key == "tourism_tax" ? "room_night" : "nightly_room_charge"
    end

    def room_transaction_code_tax_basis_amount(rule, basis_amount, quantity)
      rule.primary_tax_key == "tourism_tax" ? quantity.to_i : basis_amount
    end

    def enabled_hotel_taxes
      @enabled_hotel_taxes ||= @hotel.hotel_taxes.enabled.to_a
    end

    def tax_posting_for(tax, date, basis_amount)
      amount = tax.rate_type == "percentage" ? (basis_amount * tax.amount.to_d / 100).round(2) : tax.amount.to_d
      transaction_code = tax.ensure_transaction_code

      {
        "tax_id" => tax.id,
        "name" => tax.name,
        "type" => "custom",
        "transaction_code_id" => transaction_code.id,
        "transaction_code_system_key" => transaction_code.system_key,
        "transaction_code_code" => transaction_code.code,
        "rate_type" => tax.rate_type,
        "rate" => tax.amount.to_d,
        "basis" => tax.rate_type == "percentage" ? "nightly_room_charge" : "booking",
        "basis_amount" => basis_amount,
        "amount" => amount,
        "currency" => @hotel.default_currency.presence || "MYR",
        "posting_schedule" => "nightly",
        "stay_date" => date.iso8601,
        "guest_country" => @guest_country,
        "foreign_guests_only" => tax.foreign_guests_only,
        "source" => "hotel_tax"
      }
    end

    def sst_posting_for(date, basis_amount)
      transaction_code = transaction_code_for("sst_tax")

      {
        "name" => "Service Tax (SST 8%)",
        "type" => "sst",
        "transaction_code_id" => transaction_code&.id,
        "transaction_code_system_key" => transaction_code&.system_key,
        "transaction_code_code" => transaction_code&.code,
        "rate_type" => "percentage",
        "rate" => 8.to_d,
        "basis" => "nightly_room_charge",
        "basis_amount" => basis_amount,
        "amount" => (basis_amount * 0.08).round(2),
        "currency" => @hotel.default_currency.presence || "MYR",
        "posting_schedule" => "nightly",
        "stay_date" => date.iso8601,
        "guest_country" => @guest_country,
        "source" => "hotel_sst"
      }
    end

    def tourism_posting_for(date, amount)
      transaction_code = transaction_code_for("tourism_tax")

      {
        "name" => "Tourism Tax",
        "type" => "tourism_tax",
        "transaction_code_id" => transaction_code&.id,
        "transaction_code_system_key" => transaction_code&.system_key,
        "transaction_code_code" => transaction_code&.code,
        "rate_type" => "flat",
        "basis" => "room_night",
        "basis_amount" => 1,
        "amount" => amount,
        "currency" => @hotel.default_currency.presence || "MYR",
        "posting_schedule" => "nightly",
        "stay_date" => date.iso8601,
        "guest_country" => @guest_country,
        "source" => "hotel_tourism_tax"
      }
    end

    def stringify_amounts(item)
      item.transform_values do |value|
        value.is_a?(BigDecimal) ? value.to_s("F") : value
      end
    end

    def transaction_code_for(system_key)
      Financials::EnsureDefaultTransactionCodes.call(@hotel)
      @hotel.transaction_codes.find_by(system_key: system_key)
    end

    def summarize_tax_lines(tax_posting_snapshot)
      grouped = tax_posting_snapshot.values.flatten.group_by { |item| [ item["name"], item["type"], item["source"] ] }

      grouped.map do |(name, type, source), items|
        first_item = items.first
        {
          "name" => name,
          "type" => type,
          "source" => source,
          "transaction_code_id" => first_item["transaction_code_id"],
          "transaction_code_system_key" => first_item["transaction_code_system_key"],
          "transaction_code_code" => first_item["transaction_code_code"],
          "amount" => items.sum { |item| item["amount"].to_d }.round(2).to_s("F")
        }.compact
      end
    end
  end
end
