# frozen_string_literal: true

module ChannelManagers
  # Applies the OTA collection side of a channel settlement. The settlement
  # allocation is the idempotency boundary; the folio transaction uses the
  # same deterministic operation key so a repeated webhook cannot create a
  # second credit.
  class ApplyOtaSettlement
    Result = ApplicationResult.define(:allocation, :folio, :transaction)
    ManyResult = ApplicationResult.define(:results, :allocations, :folios, :transactions)
    GroupConversionResult = ApplicationResult.define(:conversions)

    def self.call(booking:, settlement:)
      new(booking:, settlement:).call
    end

    def self.call!(booking:, settlement:)
      new(booking:, settlement:).call!
    end

    # Applies one persisted settlement to a collection of bookings. This is
    # provider-neutral: the caller supplies the bookings returned by ingestion.
    # Group bookings are allocated by total_amount, with the final booking
    # receiving each currency remainder so the allocation sums exactly to the
    # persisted settlement.
    def self.call_many(bookings:, settlement:)
      new(booking: nil, settlement:).call_many(bookings:)
    end

    class << self
      alias call_for_bookings call_many
    end

    PostingConversion = Data.define(:amount, :rate, :source, :source_currency, :target_currency, :rounding_amount) do
      def success? = true
      def error = nil
    end

    def initialize(booking:, settlement:, gross_amount: nil, commission_amount: nil, posting_conversion: nil)
      @booking = booking
      @settlement = settlement
      @gross_amount = gross_amount&.to_d
      @commission_amount = commission_amount&.to_d
      @posting_conversion = posting_conversion
    end

    def call!
      result = call
      raise ArgumentError, result.error unless result.success?

      result
    end

    def call_many(bookings:)
      return ManyResult.success(results: []) unless settlement_eligible?

      bookings = normalized_bookings(bookings)
      amounts = allocation_amounts(bookings)
      conversions = group_posting_conversions(bookings, amounts)
      return ManyResult.failure(conversions.error, results: [], allocations: [], folios: [], transactions: []) unless conversions.success?

      results = []
      failed = nil
      ActiveRecord::Base.transaction do
        results = bookings.zip(amounts, conversions.conversions).map do |booking, (gross_amount, commission_amount), posting_conversion|
          self.class.new(
            booking: booking,
            settlement: @settlement,
            gross_amount: gross_amount,
            commission_amount: commission_amount,
            posting_conversion: posting_conversion
          ).call
        end
        failed = results.find { |result| !result.success? }
        raise ActiveRecord::Rollback if failed
      end

      attributes = {
        results: results,
        allocations: results.filter_map(&:allocation),
        folios: results.filter_map(&:folio),
        transactions: results.filter_map(&:transaction)
      }
      return ManyResult.failure(failed.error, **attributes) if failed

      ManyResult.success(**attributes)
    rescue StandardError => e
      ManyResult.failure(e.message, results: [], allocations: [], folios: [], transactions: [])
    end

    def call
      return Result.success unless valid_booking_and_settlement?
      return Result.success unless @settlement.collection_by == "ota"

      allocation = nil
      folio = nil
      transaction = nil

      ActiveRecord::Base.transaction do
        @booking.with_lock do
          validate_tenant!
          folio = Folios::Lifecycle::EnsureOtaFolio.call!(
            booking: @booking,
            booking_source: @settlement.booking_source,
            actor: nil
          )
          allocation = ensure_allocation!(folio)

          # A cancellation webhook does not prove that the OTA refunded the
          # guest. Preserve any already-posted credit, but never manufacture a
          # refund (or a new credit for an initial cancellation). A booking
          # removed from a group is also cancelled and must not receive a new
          # credit from a later group revision.
          operation_key = operation_key_for(allocation)
          transaction = existing_credit(folio, allocation, operation_key)
          if transaction.blank? && !@settlement.cancelled? && @booking.status != "cancelled" && gross_amount.positive?
            conversion = @posting_conversion || ConvertSettlementCurrency.call(
              amount: gross_amount,
              settlement: @settlement,
              target_currency: folio.currency
            )
            raise ArgumentError, conversion.error unless conversion.success?

            transaction = post_credit!(folio, allocation, operation_key, conversion)
          end
        end
      end

      Result.success(allocation:, folio:, transaction:)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ArgumentError => e
      Result.failure(e.message, allocation:, folio:, transaction:)
    rescue StandardError => e
      Result.failure(e.message, allocation:, folio:, transaction:)
    end

    private

    def settlement_eligible?
      @settlement.is_a?(ChannelSettlement) && @settlement.persisted? && @settlement.collection_by == "ota"
    end

    def normalized_bookings(bookings)
      Array(bookings).compact
        .select { |booking| booking.is_a?(Booking) && booking.persisted? && booking.status != "cancelled" }
        .uniq { |booking| booking.id }
        .sort_by { |booking| [ booking.group_position || Float::INFINITY, booking.id ] }
    end

    def group_posting_conversions(bookings, amounts)
      return GroupConversionResult.success(conversions: []) if bookings.empty?

      target_currency = bookings.first.hotel.default_currency.presence || bookings.first.currency
      unless bookings.all? { |booking| (booking.hotel.default_currency.presence || booking.currency) == target_currency }
        return GroupConversionResult.failure("Group folios must share one currency", conversions: [])
      end

      total_conversion = ConvertSettlementCurrency.call(
        amount: gross_amount,
        settlement: @settlement,
        target_currency: target_currency
      )
      return GroupConversionResult.failure(total_conversion.error, conversions: []) unless total_conversion.success?

      source_weights = amounts.map { |gross, _commission| gross.to_d }
      source_weights = Array.new(bookings.length, 1.to_d) if source_weights.sum.zero?
      converted_amounts = allocate_money(total_conversion.amount, source_weights)
      conversions = converted_amounts.each_with_index.map do |amount, index|
        PostingConversion.new(
          amount: amount,
          rate: total_conversion.rate,
          source: total_conversion.source,
          source_currency: total_conversion.source_currency,
          target_currency: total_conversion.target_currency,
          rounding_amount: amount - amounts[index].first.to_d * total_conversion.rate.to_d
        )
      end
      GroupConversionResult.success(conversions: conversions)
    end

    def allocation_amounts(bookings)
      return [] if bookings.empty?

      weights = bookings.map do |booking|
        amount = booking.total_amount.to_d
        amount.positive? ? amount : BigDecimal("0")
      end
      weights = Array.new(bookings.length, BigDecimal("1")) if weights.sum.zero?

      gross_amounts = allocate_money(gross_amount, weights)
      gross_caps = gross_amounts.map { |amount| (amount.to_d * 100).round(0).to_i }
      commission_amounts = allocate_money(commission_amount, weights, caps: gross_caps)
      gross_amounts.zip(commission_amounts)
    end

    # Allocate in cents rather than repeatedly rounding BigDecimals. This
    # makes the final-line remainder deterministic and guarantees that the
    # persisted allocation totals equal the settlement totals.
    def allocate_money(total, weights, caps: nil)
      total_cents = (total.to_d * 100).round(0).to_i
      denominator = weights.sum
      allocations = Array.new(weights.length, 0)
      remaining = total_cents

      weights.each_with_index do |weight, index|
        amount = if index == weights.length - 1
          remaining
        else
          (total_cents.to_d * weight / denominator).round(0).to_i
        end
        amount = [ amount, remaining ].min
        amount = [ amount, caps[index] ].min if caps
        amount = 0 if amount.negative?
        allocations[index] = amount
        remaining -= amount
      end

      # A rounded commission line can be capped by its gross line. Push any
      # resulting remainder into earlier lines with available gross capacity.
      if remaining.positive? && caps
        allocations.each_index.reverse_each do |index|
          available = caps[index] - allocations[index]
          transfer = [ remaining, available ].min
          allocations[index] += transfer
          remaining -= transfer
          break if remaining.zero?
        end
      end

      raise ArgumentError, "Settlement allocation exceeds available gross amount" if remaining.positive?

      allocations.map { |amount| BigDecimal(amount.to_s) / 100 }
    end

    def valid_booking_and_settlement?
      return false unless @booking.is_a?(Booking) && @booking.persisted?
      return false unless @settlement.is_a?(ChannelSettlement) && @settlement.persisted?

      true
    end

    def validate_tenant!
      raise ArgumentError, "Settlement must belong to the booking hotel." unless @settlement.hotel_id == @booking.hotel_id
      raise ArgumentError, "Settlement booking source is required." if @settlement.booking_source_id.blank?
      raise ArgumentError, "Settlement booking source must be an OTA booking source." unless @settlement.booking_source.kind == "ota"
    end

    def ensure_allocation!(folio)
      allocation = @settlement.channel_settlement_allocations.lock.find_or_initialize_by(booking_id: @booking.id)
      allocation.assign_attributes(
        booking: @booking,
        booking_folio: folio,
        currency: @settlement.currency,
        gross_amount: gross_amount,
        commission_amount: commission_amount,
        expected_net_amount: gross_amount - commission_amount
      )
      allocation.save!
      allocation
    end

    def existing_credit(folio, allocation, operation_key)
      folio.folio_transactions
        .where(operation_key: operation_key)
        .where(transaction_type: "payment")
        .first || folio.folio_transactions
          .where(transaction_type: "payment")
          .find_by("metadata->>'channel_settlement_allocation_id' = ?", allocation.id.to_s)
    end

    def post_credit!(folio, allocation, operation_key, conversion)
      result = Folios::Transactions::PostStaffTransaction.call(
        folio: folio,
        user: nil,
        transaction_type: "payment",
        category: "booking_payment",
        amount: conversion.amount,
        description: "OTA settlement credit (#{stable_reference})",
        posting_date: @booking.hotel.current_business_date,
        options: {
          payment_source: "ota",
          payment_references: { ota_reference: stable_reference },
          system_posting: true,
          posting_source: "ota_credit",
          operation_key: operation_key,
          currency: folio.currency,
          metadata: {
            posting_source: "ota_credit",
            channel_settlement_id: @settlement.id,
            channel_settlement_allocation_id: allocation.id,
            booking_source_id: @settlement.booking_source_id,
            ota_reference: stable_reference,
            receipt_policy: "none",
            collection_by: "ota",
            settlement_status: @settlement.status,
            settlement_source_amount: gross_amount.to_s("F"),
            settlement_source_currency: conversion.source_currency,
            folio_posting_amount: conversion.amount.to_s("F"),
            folio_posting_currency: conversion.target_currency,
            settlement_exchange_rate: conversion.rate.to_d.to_s("F"),
            settlement_exchange_rate_source: conversion.source,
            settlement_conversion_rounding_amount: conversion.rounding_amount.to_d.to_s("F"),
            operation_key: operation_key
          }
        }
      )
      return result.transaction if result.success?

      raise "OTA settlement credit could not be posted: #{result.error}"
    end

    def gross_amount
      @gross_amount || @settlement.gross_amount.to_d
    end

    def commission_amount
      @commission_amount || @settlement.commission_amount.to_d
    end

    def stable_reference
      @stable_reference ||= @settlement.channel_manager_reference.to_s.strip
    end

    def operation_key_for(allocation)
      "ota_credit:settlement:#{@settlement.id}:allocation:#{allocation.id}"
    end
  end
end
