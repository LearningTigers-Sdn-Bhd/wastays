# frozen_string_literal: true

require "digest"
require "ostruct"

module TransactionCodes
  class HotelTaxRuleChange
    Result = Data.define(
      :changed?, :before_keys, :after_keys, :added_keys, :removed_keys,
      :added_labels, :removed_labels, :forecast_count, :forecast_amount,
      :forecast_policy, :freshness_token
    )

    def self.preview(transaction_code:, proposed_keys:)
      new(transaction_code:, proposed_keys:).preview
    end

    def self.verify_freshness(transaction_code:, proposed_keys:, token:)
      new(transaction_code:, proposed_keys:).verify_freshness(token)
    end

    def initialize(transaction_code:, proposed_keys:)
      @transaction_code = transaction_code
      @hotel = transaction_code.hotel
      @proposed_keys = Array(proposed_keys).reject(&:blank?).map(&:to_s).uniq.sort
    end

    def preview
      validate_keys!
      before = current_keys
      added = @proposed_keys - before
      removed = before - @proposed_keys
      impact = forecast_impact

      Result.new(
        changed?: before != @proposed_keys,
        before_keys: before,
        after_keys: @proposed_keys,
        added_keys: added,
        removed_keys: removed,
        added_labels: labels_for(added),
        removed_labels: labels_for(removed),
        forecast_count: impact[:count],
        forecast_amount: impact[:amount],
        forecast_policy: forecast_policy,
        freshness_token: verifier.generate(freshness_payload(before))
      )
    end

    def verify_freshness(token)
      payload = verifier.verify(token.to_s)
      ActiveSupport::SecurityUtils.secure_compare(
        payload.fetch("digest"),
        freshness_payload(current_keys).fetch("digest")
      ) && payload.fetch("transaction_code_id") == @transaction_code.id
    rescue ActiveSupport::MessageVerifier::InvalidSignature, KeyError
      false
    end

    private

    def validate_keys!
      invalid = @proposed_keys - available_rules.keys
      raise ArgumentError, "A selected tax rule is unavailable for this hotel." if invalid.any?
    end

    def current_keys
      @transaction_code.transaction_code_taxes.reload.map(&:tax_rule_key).sort
    end

    def available_rules
      @available_rules ||= begin
        primary = {
          "primary:sst_tax" => "SST 8%",
          "primary:tourism_tax" => "Tourism Tax"
        }
        custom = @hotel.hotel_taxes.pluck(:id, :name).to_h do |id, name|
          [ "hotel_tax:#{id}", name ]
        end
        primary.merge(custom)
      end
    end

    def labels_for(keys)
      keys.map { |key| available_rules.fetch(key) }
    end

    def forecast_policy
      return "future_manual_postings" unless room_revenue?

      @hotel.transaction_configuration.room_revenue_tax_rule_application
    end

    def forecast_impact
      return { count: 0, amount: 0.to_d } unless room_revenue?
      return { count: 0, amount: 0.to_d } unless @hotel.transaction_configuration.open_folio_forecasts?

      forecasts = FolioForecastedCharge.forecast
        .joins(booking_folio: :booking)
        .merge(@hotel.booking_folios.open)
        .where.not(bookings: { status: Folios::Forecasts::RefreshOpenForecastsFromRoomRevenueRules::EXCLUDED_BOOKING_STATUSES })
      { count: forecasts.count, amount: forecasts.sum(:amount) }
    end

    def room_revenue?
      @transaction_code.system_key == "room_revenue"
    end

    def freshness_payload(keys)
      state = [ @transaction_code.id, @transaction_code.updated_at.to_f, keys.join(",") ].join(":")
      {
        "transaction_code_id" => @transaction_code.id,
        "digest" => Digest::SHA256.hexdigest(state)
      }
    end

    def verifier
      Rails.application.message_verifier("hotel-tax-rule-change")
    end
  end
end
