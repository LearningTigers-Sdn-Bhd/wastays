# frozen_string_literal: true

require "ostruct"

module TransactionCodes
  class ApplyHotelTaxRuleChange
    def self.call(transaction_code:, actor:, attributes:, proposed_keys:, reason:, freshness_token:)
      new(transaction_code:, actor:, attributes:, proposed_keys:, reason:, freshness_token:).call
    end

    def initialize(transaction_code:, actor:, attributes:, proposed_keys:, reason:, freshness_token:)
      @transaction_code = transaction_code
      @hotel = transaction_code.hotel
      @actor = actor
      @attributes = attributes
      @proposed_keys = Array(proposed_keys).reject(&:blank?).map(&:to_s).uniq.sort
      @reason = reason.to_s.strip
      @freshness_token = freshness_token
    end

    def call
      return failure("Reason is required for a hotel-wide tax inclusion change.") if @reason.blank?

      preview = HotelTaxRuleChange.preview(transaction_code: @transaction_code, proposed_keys: @proposed_keys)
      unless HotelTaxRuleChange.verify_freshness(transaction_code: @transaction_code, proposed_keys: @proposed_keys, token: @freshness_token)
        return failure("Transaction code tax rules changed after this review. Review the latest configuration and try again.")
      end

      refresh_result = nil
      TransactionCode.transaction do
        @transaction_code.reload
        @transaction_code.lock!
        @transaction_code.update!(@attributes)
        replace_tax_rules!
        refresh_result = refresh_forecasts_if_needed
        record_audit!(preview, refresh_result)
      end
      success(refresh_result)
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      failure(e.message)
    end

    private

    def replace_tax_rules!
      @transaction_code.transaction_code_taxes.destroy_all
      @proposed_keys.each do |key|
        if key.start_with?("primary:")
          @transaction_code.transaction_code_taxes.create!(primary_tax_key: key.delete_prefix("primary:"))
        else
          tax = @hotel.hotel_taxes.find(key.delete_prefix("hotel_tax:"))
          @transaction_code.transaction_code_taxes.create!(hotel_tax: tax)
        end
      end
    end

    def refresh_forecasts_if_needed
      return unless @transaction_code.system_key == "room_revenue"
      return unless @hotel.transaction_configuration.open_folio_forecasts?

      Folios::Forecasts::RefreshOpenForecastsFromRoomRevenueRules.call(hotel: @hotel, actor: @actor)
    end

    def record_audit!(preview, refresh_result)
      FinancialControls::AuditEventRecorder.call!(
        hotel: @hotel,
        business_date: @hotel.current_business_date,
        event_type: "hotel_tax_rules_changed",
        source: "transaction_codes",
        actor: @actor,
        reason: @reason,
        metadata: {
          transaction_code_id: @transaction_code.id,
          transaction_code: @transaction_code.code,
          before_tax_rule_keys: preview.before_keys,
          after_tax_rule_keys: @proposed_keys,
          forecast_policy: preview.forecast_policy,
          forecasts_changed: refresh_result&.forecasts_changed.to_i
        }
      )
    end

    def success(refresh_result)
      OpenStruct.new(success?: true, transaction_code: @transaction_code, refresh_result:, error: nil)
    end

    def failure(error)
      OpenStruct.new(success?: false, transaction_code: @transaction_code, refresh_result: nil, error:)
    end
  end
end
