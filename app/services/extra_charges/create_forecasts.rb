# frozen_string_literal: true

require "securerandom"

module ExtraCharges
  class CreateForecasts
    Result = ApplicationResult.define(:forecasts, :quote, :posting_group_key)

    def self.call(extra_charge:, folio:, booking:, starts_on:, ends_on:, unit_rate:, expected_fingerprint:, description: nil, reference: nil, note: nil, user: nil)
      new(extra_charge:, folio:, booking:, starts_on:, ends_on:, unit_rate:, expected_fingerprint:, description:, reference:, note:, user:).call
    end

    def initialize(extra_charge:, folio:, booking:, starts_on:, ends_on:, unit_rate:, expected_fingerprint:, description:, reference:, note:, user:)
      @extra_charge = extra_charge
      @folio = folio
      @booking = booking
      @starts_on = starts_on
      @ends_on = ends_on
      @unit_rate = unit_rate
      @expected_fingerprint = expected_fingerprint
      @submitted_description = description
      @reference = reference.to_s.strip.presence
      @note = note.to_s.strip.presence
      @user = user
      @posting_group_key = SecureRandom.uuid
    end

    def call
      quote = ForecastQuote.call(
        extra_charge: @extra_charge,
        folio: @folio,
        booking: @booking,
        starts_on: @starts_on,
        ends_on: @ends_on,
        unit_rate: @unit_rate,
        expected_fingerprint: @expected_fingerprint
      )
      return Result.failure(quote.error, quote: quote) unless quote.success?

      forecasts = []
      ActiveRecord::Base.transaction do
        @booking.with_lock do
          quote.dates.each { |row| forecasts.concat(create_date_forecasts(row)) }
        end
      end
      Result.success(forecasts: forecasts, quote: quote, posting_group_key: @posting_group_key)
    rescue ActiveRecord::RecordInvalid => error
      Result.failure(error.record.errors.full_messages.to_sentence, quote: quote)
    end

    private

    def create_date_forecasts(row)
      description = Description.call(
        extra_charge: @extra_charge,
        currency: @folio.currency,
        amount: row[:base_amount],
        calculated_amount: row[:base_amount],
        quantity: row[:quantity],
        unit_rate: row[:unit_rate],
        date: row[:date],
        submitted_description: @submitted_description
      )
      base = create_forecast!(
        folio_id: row[:base_target_folio_id],
        date: row[:date],
        kind: "extra_charge",
        identity: "extra-charge:#{@posting_group_key}:base",
        amount: row[:base_amount],
        description: description,
        metadata: common_metadata.merge(
          line_key: "base",
          quantity: row[:quantity],
          unit_rate: row[:unit_rate].to_s("F"),
          category: @extra_charge.category,
          transaction_code_id: @extra_charge.transaction_code_id,
          transaction_code_code: @extra_charge.code,
          transaction_code_name: @extra_charge.name
        )
      )

      taxes = row[:taxes].map do |tax|
        create_forecast!(
          folio_id: tax[:target_folio_id],
          date: row[:date],
          kind: "extra_charge_tax",
          identity: "extra-charge:#{@posting_group_key}:#{tax[:line_key]}",
          amount: tax[:amount],
          description: "Tax: #{tax[:name]} for #{description}",
          metadata: common_metadata.merge(tax).merge(
            parent_forecast_id: base.id,
            parent_identity: base.identity,
            category: "tax",
            line_key: tax[:line_key]
          )
        )
      end
      [ base, *taxes ]
    end

    def common_metadata
      {
        source: "staff_extra_charge",
        extra_charge_posting_key: @posting_group_key,
        extra_charge_id: @extra_charge.id,
        charging_unit: @extra_charge.charging_unit,
        configured_rate: @extra_charge.rate_value.to_d.to_s("F"),
        reference: @reference,
        note: @note,
        approved_by_user_id: @user&.id
      }.compact
    end

    def create_forecast!(folio_id:, date:, kind:, identity:, amount:, description:, metadata:)
      FolioForecastedCharge.create!(
        booking_folio_id: folio_id,
        stay_date: date,
        charge_kind: kind,
        identity: identity,
        amount: amount,
        description: description,
        metadata: metadata
      )
    end
  end
end
