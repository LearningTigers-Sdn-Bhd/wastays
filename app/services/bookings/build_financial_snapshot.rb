# frozen_string_literal: true

require "ostruct"

module Bookings
  class BuildFinancialSnapshot
    def initialize(hotel:, check_in:, check_out:, guest_country:, room_type: nil, rate_plan: nil, quantity: 1, manual_total_amount: nil, nightly_rate_snapshot: nil, room_items: nil)
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
      rates = @room_type.room_rates.where(date: stay_dates, currency: currency)
      rates = @rate_plan.present? ? rates.where(rate_plan: @rate_plan) : rates.where(rate_plan_id: nil)
      rates_by_date = rates.index_by(&:date)
      missing_dates = stay_dates - rates_by_date.keys
      raise ArgumentError, "Missing room rates for #{missing_dates.map(&:iso8601).join(', ')}." if missing_dates.any?

      snapshot = stay_dates.index_with do |date|
        rate = rates_by_date.fetch(date)
        rate.as_json.merge(
          "room_rate_id" => rate.id,
          "source" => "room_rate",
          "price" => rate.price.to_d.to_s("F"),
          "currency" => rate.currency
        )
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
      snapshot = Hash.new { |hash, key| hash[key] = [] }

      rooms.each do |room|
        stay_dates.each do |date|
          date_key = date.iso8601
          basis_amount = room[:nightly_rate_snapshot].dig(date_key, "price").to_d * room[:quantity]
          next unless basis_amount.positive?

          enabled_hotel_taxes.select { |tax| tax.rate_type == "percentage" }.each do |tax|
            next unless tax.applicable_for?(@guest_country)

            snapshot[date_key] << tax_posting_for(tax, date, basis_amount)
          end

          if @hotel.sst_enabled?
            snapshot[date_key] << sst_posting_for(date, basis_amount)
          end

          tourism_amount = @hotel.tourism_tax_amount_for(@guest_country).to_d
          if tourism_amount.positive?
            snapshot[date_key] << tourism_posting_for(date, tourism_amount * room[:quantity])
          end
        end
      end

      enabled_hotel_taxes.select { |tax| tax.rate_type == "flat" }.each do |tax|
        next unless tax.applicable_for?(@guest_country)

        snapshot[@check_in.iso8601] << tax_posting_for(tax, @check_in, rooms.sum { |room| room[:total_amount] })
      end

      snapshot.transform_values { |items| items.map { |item| stringify_amounts(item) } }
    end

    def enabled_hotel_taxes
      @enabled_hotel_taxes ||= @hotel.hotel_taxes.enabled.to_a
    end

    def tax_posting_for(tax, date, basis_amount)
      amount = tax.rate_type == "percentage" ? (basis_amount * tax.amount.to_d / 100).round(2) : tax.amount.to_d

      {
        "tax_id" => tax.id,
        "name" => tax.name,
        "type" => "custom",
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
      {
        "name" => "Service Tax (SST 8%)",
        "type" => "sst",
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
      {
        "name" => "Tourism Tax",
        "type" => "tourism_tax",
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

    def summarize_tax_lines(tax_posting_snapshot)
      grouped = tax_posting_snapshot.values.flatten.group_by { |item| [ item["name"], item["type"], item["source"] ] }

      grouped.map do |(name, type, source), items|
        {
          "name" => name,
          "type" => type,
          "source" => source,
          "amount" => items.sum { |item| item["amount"].to_d }.round(2).to_s("F")
        }
      end
    end
  end
end
