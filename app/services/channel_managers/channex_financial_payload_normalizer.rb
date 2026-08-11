# frozen_string_literal: true

require "bigdecimal"
require "date"

module ChannelManagers
  # Converts the financial portion of a Channex booking revision into a stable,
  # provider-independent hash. It deliberately does not retain payment-card or
  # arbitrary provider data.
  class ChannexFinancialPayloadNormalizer
    TOP_LEVEL_METADATA = %w[
      booking_id ota_reservation_id unique_id revision_id ota_name status
      arrival_date departure_date inserted_at updated_at source payment_collect
      payment_type
    ].freeze
    ROOM_METADATA = %w[ota_room_id room_name meal_plan].freeze
    CHARGE_METADATA = %w[
      code name title type category currency price_mode rate percent percentage
      basis scope applied_to nights persons price_per_unit
    ].freeze

    MONEY_KEYS = %w[amount price rate total total_price value].freeze

    def self.call(payload)
      new(payload).call
    end

    def initialize(payload)
      @payload = stringify_hash(payload)
    end

    def call
      source = booking_attributes
      rooms = Array(source["rooms"]).filter_map.with_index { |room, index| normalize_room(room, index) }
      top_tax_entries = normalize_charges(source["taxes"] || source.dig("fees", "taxes"), kind: "tax")
      taxes = top_tax_entries.select { |charge| charge[:kind] == "tax" }
      service_fees = top_tax_entries.select { |charge| charge[:kind] == "service_fee" } + normalize_charges(
        source["services"] || source["service_fees"] || source.dig("fees", "services"),
        kind: "service_fee"
      )
      discounts = normalize_charges(source["discounts"], kind: "discount")
      all_taxes = taxes + rooms.flat_map { |room| room[:taxes] + room[:days].flat_map { |day| day[:taxes] } }
      all_fees = service_fees + rooms.flat_map { |room| room[:service_fees] + room[:days].flat_map { |day| day[:service_fees] } }
      all_discounts = discounts + rooms.flat_map { |room| room[:discounts] + room[:days].flat_map { |day| day[:discounts] } }
      room_amount = rooms.sum(DECIMAL_ZERO) { |room| room[:amount] }

      {
        currency: normalized_currency(source["currency"]),
        gross_amount: decimal(source["amount"] || source["total_amount"]),
        commission_amount: decimal(source["ota_commission"] || source["commission_amount"] || source["commission"]),
        payment_collect: present_string(source["payment_collect"]),
        breakdown_present: breakdown_present?(source),
        breakdown_complete: breakdown_complete?(source),
        occupancy: normalize_occupancy(source["occupancy"] || source),
        rooms: rooms,
        taxes: taxes,
        service_fees: service_fees,
        discounts: discounts,
        totals: {
          room_amount: room_amount,
          tax_amount: sum_amounts(all_taxes),
          inclusive_tax_amount: sum_amounts(all_taxes.select { |charge| charge[:inclusive] }),
          exclusive_tax_amount: sum_amounts(all_taxes.reject { |charge| charge[:inclusive] }),
          service_fee_amount: sum_amounts(all_fees),
          inclusive_service_fee_amount: sum_amounts(all_fees.select { |charge| charge[:inclusive] }),
          exclusive_service_fee_amount: sum_amounts(all_fees.reject { |charge| charge[:inclusive] }),
          discount_amount: sum_amounts(all_discounts),
          calculated_amount: room_amount +
            sum_amounts(all_taxes.reject { |charge| charge[:inclusive] }) +
            sum_amounts(all_fees.reject { |charge| charge[:inclusive] }) -
            sum_amounts(all_discounts)
        },
        metadata: whitelisted(source, TOP_LEVEL_METADATA)
      }
    end

    private

    DECIMAL_ZERO = BigDecimal("0")

    def booking_attributes
      raw = @payload["data"] || @payload
      raw = stringify_hash(raw)
      stringify_hash(raw["attributes"] || raw)
    end

    def breakdown_present?(source)
      source.key?("amount") || source.key?("total_amount") || Array(source["rooms"]).any?
    end

    def breakdown_complete?(source)
      gross_present = source.key?("amount") || source.key?("total_amount")
      rooms = Array(source["rooms"])
      gross_present && normalized_currency(source["currency"]).present? && rooms.any? && rooms.all? do |value|
        room = stringify_hash(value)
        money_value(room).present? || days_have_amounts?(room["days"])
      end
    end

    def days_have_amounts?(value)
      entries = value.is_a?(Hash) ? value.values : Array(value)
      entries.any? && entries.all? do |entry|
        entry.is_a?(Hash) ? money_value(stringify_hash(entry)).present? : entry.present?
      end
    end

    def normalize_room(value, index)
      room = stringify_hash(value)
      return if room.empty?

      days = normalize_days(room["days"])
      provider_room_gross = decimal(money_value(room))
      room_amount = if days.any?
        days.sum(DECIMAL_ZERO) { |day| day[:amount] }
      else
        provider_room_gross
      end
      room_tax_entries = normalize_charges(room["taxes"], kind: "tax")

      {
        position: index + 1,
        room_type_id: present_string(room["room_type_id"]),
        rate_plan_id: present_string(room["rate_plan_id"]),
        quantity: positive_integer(room["count"] || room["quantity"] || 1),
        occupancy: normalize_occupancy(room["occupancy"] || room),
        amount: room_amount,
        gross_amount: provider_room_gross,
        days: days,
        taxes: room_tax_entries.select { |charge| charge[:kind] == "tax" },
        service_fees: room_tax_entries.select { |charge| charge[:kind] == "service_fee" } +
          normalize_charges(room["services"] || room["service_fees"], kind: "service_fee"),
        discounts: normalize_charges(room["discounts"], kind: "discount"),
        metadata: whitelisted(room, ROOM_METADATA)
      }
    end

    def normalize_days(value)
      entries = case value
      when Array
        value
      when Hash
        value.map do |date, details|
          details.is_a?(Hash) ? stringify_hash(details).merge("date" => date.to_s) : { "date" => date.to_s, "amount" => details }
        end
      else
        []
      end

      entries.filter_map do |entry|
        day = stringify_hash(entry)
        date = normalized_date(day["date"] || day["stay_date"])
        next unless date

        tax_entries = normalize_charges(day["taxes"], kind: "tax")
        {
          date: date,
          amount: decimal(money_value(day)),
          occupancy: normalize_occupancy(day["occupancy"] || day),
          taxes: tax_entries.select { |charge| charge[:kind] == "tax" },
          service_fees: tax_entries.select { |charge| charge[:kind] == "service_fee" } +
            normalize_charges(day["services"] || day["service_fees"], kind: "service_fee"),
          discounts: normalize_charges(day["discounts"], kind: "discount")
        }
      end.sort_by { |day| day[:date] }
    end

    def normalize_charges(value, kind:)
      entries = value.is_a?(Hash) ? value.map { |name, amount| { "name" => name, "amount" => amount } } : Array(value)
      entries.filter_map do |entry|
        charge = entry.is_a?(Hash) ? stringify_hash(entry) : { "amount" => entry }
        amount = money_value(charge)
        next if amount.nil?

        {
          kind: classified_kind(charge, fallback: kind),
          amount: decimal(amount).abs,
          inclusive: inclusive?(charge),
          metadata: whitelisted(charge, CHARGE_METADATA)
        }
      end.sort_by { |charge| [ charge.dig(:metadata, "code").to_s, charge.dig(:metadata, "name").to_s, charge[:amount].to_s("F") ] }
    end

    def normalize_occupancy(value)
      occupancy = stringify_hash(value)
      {
        adults: nonnegative_integer(occupancy["adults"] || occupancy["adult"] || occupancy["occ_adults"]),
        children: nonnegative_integer(occupancy["children"] || occupancy["child"] || occupancy["occ_children"]),
        infants: nonnegative_integer(occupancy["infants"] || occupancy["infant"] || occupancy["occ_infants"])
      }
    end

    def classified_kind(charge, fallback:)
      classification = [ charge["type"], charge["category"], charge["name"], charge["title"] ]
        .compact.join(" ").downcase
      return "discount" if classification.match?(/discount|promotion|rebate/)
      return "service_fee" if classification.match?(/service[ _-]*charge|cleaning|service[ _-]*fee|\bfee\b/)
      return "tax" if classification.match?(/tax|vat|sst/)

      fallback
    end

    def inclusive?(charge)
      value = charge["inclusive"]
      value = charge["is_inclusive"] if value.nil?
      value = charge["included"] if value.nil?
      value == true || %w[true 1 yes included inclusive].include?(value.to_s.downcase)
    end

    def money_value(hash)
      MONEY_KEYS.each do |key|
        value = hash[key]
        return value unless value.nil? || value.to_s.strip.empty?
      end
      nil
    end

    def decimal(value)
      return DECIMAL_ZERO if value.nil? || value.to_s.strip.empty?

      BigDecimal(value.to_s.delete(","))
    rescue ArgumentError
      DECIMAL_ZERO
    end

    def sum_amounts(charges)
      charges.sum(DECIMAL_ZERO) { |charge| charge[:amount] }
    end

    def normalized_currency(value)
      currency = value.to_s.strip.upcase
      currency.match?(/\A[A-Z]{3}\z/) ? currency : nil
    end

    def normalized_date(value)
      Date.iso8601(value.to_s).iso8601
    rescue Date::Error
      nil
    end

    def positive_integer(value)
      number = value.to_i
      number.positive? ? number : 1
    end

    def nonnegative_integer(value)
      [ value.to_i, 0 ].max
    end

    def present_string(value)
      string = value.to_s.strip
      string.empty? ? nil : string
    end

    def whitelisted(source, keys)
      keys.each_with_object({}) do |key, result|
        value = source[key]
        next if value.nil? || value.is_a?(Hash) || value.is_a?(Array)

        result[key] = value.to_s.first(255) if value.is_a?(String)
        result[key] = value if value.is_a?(Numeric) || value == true || value == false
      end
    end

    def stringify_hash(value)
      return {} unless value.respond_to?(:each_pair)

      value.each_pair.to_h { |key, item| [ key.to_s, item ] }
    end
  end
end
