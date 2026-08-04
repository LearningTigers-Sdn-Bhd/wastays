# frozen_string_literal: true

module Deposits
  class ConfiguredPrepayment
    Result = ApplicationResult.define(:deposit, :movements, :collected_total)

    def self.call(owner:, folios:, base_amount:, payment_method_id:, actor:, external_reference: nil,
      posting_date: nil, override_night_audit: false, override_reason: nil, operation_key:)
      new(
        owner:, folios:, base_amount:, payment_method_id:, actor:, external_reference:, posting_date:,
        override_night_audit:, override_reason:, operation_key:
      ).call
    end

    def initialize(owner:, folios:, base_amount:, payment_method_id:, actor:, external_reference:, posting_date:,
      override_night_audit:, override_reason:, operation_key:)
      @owner = owner
      @folios = Array(folios).compact.uniq
      @base_amount = base_amount.to_d.round(2)
      @payment_method_id = payment_method_id
      @actor = actor
      @external_reference = external_reference.to_s.strip.presence
      @posting_date = posting_date
      @override_night_audit = override_night_audit
      @override_reason = override_reason
      @operation_key = operation_key
    end

    def call
      return failure("Payment amount must be greater than 0.") unless @base_amount.positive?
      return failure("Payment cannot be applied without a folio.") if @folios.empty?

      method_result = PaymentMethods::Eligibility.call(
        hotel: @owner.hotel, id: @payment_method_id, purpose: :guest_advance
      )
      return failure(method_result.error) unless method_result.success?

      @payment_method = method_result.payment_method
      ActiveRecord::Base.transaction do
        base_amounts = base_amounts_by_folio
        surcharge_result = Folios::Payments::PostConfiguredSurcharge.call(
          folio: @folios.first,
          payment_method: @payment_method,
          base_amount: @base_amount,
          user: @actor,
          posting_date: @posting_date,
          operation_key: "#{@operation_key}:surcharge",
          metadata: payment_metadata,
          override_night_audit: @override_night_audit,
          override_reason: @override_reason
        )
        raise CreationFailed, surcharge_result.error unless surcharge_result.success?

        surcharge_amount = surcharge_result.surcharge_amount.to_d
        surcharge_tax_total = surcharge_result.surcharge_tax_total.to_d
        collected_total = (@base_amount + surcharge_amount + surcharge_tax_total).round(2)
        metadata = payment_metadata.merge(
          payment_base_amount: @base_amount.to_s("F"),
          payment_surcharge_amount: surcharge_amount.to_s("F"),
          payment_surcharge_tax_amount: surcharge_tax_total.to_s("F"),
          payment_collected_total: collected_total.to_s("F")
        )
        receipt = Deposits::Record.call(
          owner: @owner,
          kind: "prepayment",
          amount: collected_total,
          currency: @owner.hotel.default_currency || "MYR",
          payment_method: "cash",
          hotel_payment_method_id: @payment_method.id,
          actor: @actor,
          external_reference: @external_reference,
          received_at: payment_received_at,
          operation_key: "#{@operation_key}:receive",
          metadata:
        )
        raise CreationFailed, receipt.error unless receipt.success?

        application = if @folios.one?
          Deposits::Apply.call(
            deposit: receipt.deposit,
            booking_folio: @folios.first,
            amount: collected_total,
            actor: @actor,
            posting_date: @posting_date,
            override_night_audit: @override_night_audit,
            override_reason: @override_reason,
            operation_key: @operation_key,
            metadata: metadata
          )
        else
          Deposits::ApplyAcrossFolios.call(
            deposit: receipt.deposit,
            folios: @folios,
            amount: collected_total,
            strategy: "manual",
            actor: @actor,
            manual_amounts: manual_amounts(base_amounts, collected_total),
            operation_key: @operation_key,
            posting_date: @posting_date,
            override_night_audit: @override_night_audit,
            override_reason: @override_reason,
            metadata: metadata
          )
        end
        raise CreationFailed, application.error unless application.success?

        @result = Result.success(deposit: receipt.deposit, movements: application.respond_to?(:movements) ? application.movements : [ application.movement ], collected_total: collected_total)
      end
      @result
    rescue CreationFailed, ActiveRecord::RecordInvalid => e
      failure(e.message)
    end

    private

    class CreationFailed < StandardError; end

    def base_amounts_by_folio
      return { @folios.first => @base_amount } if @folios.one?

      allocate(@base_amount, @folios.index_with { |folio| folio.booking.total_amount.to_d })
    end

    def allocate(total, weights)
      positive_weights = weights.transform_values { |value| [ value.to_d, 0.to_d ].max }
      denominator = positive_weights.values.sum
      return weights.transform_values { 0.to_d } unless denominator.positive?

      remaining = total.to_d
      positive_weights.each_with_index.to_h do |(key, weight), index|
        amount = index == positive_weights.length - 1 ? remaining : ((total.to_d * weight) / denominator).round(2).clamp(0, remaining)
        remaining -= amount
        [ key, amount ]
      end
    end

    def manual_amounts(base_amounts, collected_total)
      allocate(collected_total, base_amounts).to_h do |folio, amount|
        [ folio.id.to_s, amount.round(2) ]
      end
    end

    def payment_metadata
      {
        source: "configured_booking_prepayment",
        hotel_payment_method_id: @payment_method.id,
        payment_method_name: @payment_method.name,
        payment_method_code: @payment_method.code,
        payment_method_type: @payment_method.payment_method_type
      }
    end

    def payment_received_at
      return Time.current if @posting_date.blank?

      @posting_date.to_date.in_time_zone(@owner.hotel.hotel_time_zone) + 12.hours
    rescue ArgumentError, TypeError
      Time.current
    end

    def failure(message)
      Result.failure(message, deposit: nil, movements: [], collected_total: 0.to_d)
    end
  end
end
