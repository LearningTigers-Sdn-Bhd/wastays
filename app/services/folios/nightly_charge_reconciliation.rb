# frozen_string_literal: true

require "ostruct"

module Folios
  class NightlyChargeReconciliation
    def self.call(booking:, business_date:)
      new(booking: booking, business_date: business_date).call
    end

    def initialize(booking:, business_date:)
      @booking = booking
      @business_date = business_date.to_date
    end

    def call
      entries = expected_lines.map { |line| entry_for(line) }
      OpenStruct.new(
        valid?: entries.all? { |entry| entry[:issues].empty? },
        entries: entries,
        issues: entries.flat_map { |entry| entry[:issues] }
      )
    end

    private

    def expected_lines
      @expected_lines ||= ForecastedChargeLines.call(booking: @booking, dates: [ @business_date ])
    end

    def entry_for(line)
      key = nightly_charge_key(line)
      route = resolve_route(line)
      transactions = transactions_by_key[key] || []
      valid_transactions = transactions.select { |transaction| transaction_matches?(transaction, line, route) }

      {
        line: line,
        nightly_charge_key: key,
        route: route,
        transactions: transactions,
        valid_transactions: valid_transactions,
        issues: issues_for(line, key, route, transactions, valid_transactions)
      }
    end

    def resolve_route(line)
      return OpenStruct.new(success?: false, folio: nil, route_source: nil, route_metadata: {}, error: "Missing transaction code") if line[:transaction_code].blank?

      ResolveTargetFolio.call(
        booking: @booking,
        transaction_code: line[:transaction_code],
        fallback_transaction_code: line[:fallback_transaction_code]
      )
    end

    def transactions_by_key
      @transactions_by_key ||= active_nightly_transactions.group_by do |transaction|
        transaction.metadata["nightly_charge_key"].presence ||
          transaction.metadata["reconciles_nightly_charge_key"].presence
      end
    end

    def active_nightly_transactions
      FolioTransaction
        .joins(:booking_folio)
        .includes(:booking_folio, :transaction_code)
        .where(booking_folios: { booking_id: @booking.id })
        .charge
        .where(voided_by_transaction_id: nil)
        .where(
          "folio_transactions.metadata ? 'nightly_charge_key' OR folio_transactions.metadata ? 'reconciles_nightly_charge_key'"
        )
        .to_a
    end

    def issues_for(line, key, route, transactions, valid_transactions)
      issue_types = []
      issue_types << "unresolved_route" unless route.success?
      issue_types << "missing" if transactions.empty?
      issue_types << "duplicate" if transactions.many?

      transactions.each do |transaction|
        issue_types.concat(transaction_mismatches(transaction, line, route))
      end

      issue_types << "duplicate" if valid_transactions.many?
      return [] if issue_types.empty? && valid_transactions.one?

      [ {
        "nightly_charge_key" => key,
        "stay_date" => line[:stay_date].iso8601,
        "charge_kind" => line[:charge_kind],
        "identity" => line[:identity].to_s,
        "description" => line[:description],
        "issue_types" => issue_types.uniq,
        "expected_amount" => line[:amount].to_d.to_s("F"),
        "expected_category" => line[:category],
        "expected_transaction_code_id" => line[:transaction_code]&.id,
        "expected_transaction_code_code" => line[:transaction_code]&.code,
        "expected_folio_id" => route.folio&.id,
        "expected_folio_reference" => route.folio&.folio_reference_display,
        "route_source" => route.route_source,
        "route_error" => route.error,
        "actual_transactions" => transactions.map { |transaction| serialize_transaction(transaction) }
      }.compact ]
    end

    def transaction_matches?(transaction, line, route)
      route.success? && transaction_mismatches(transaction, line, route).empty?
    end

    def transaction_mismatches(transaction, line, route)
      mismatches = []
      mismatches << "amount_mismatch" unless transaction.amount.to_d == line[:amount].to_d
      mismatches << "category_mismatch" unless transaction.category == line[:category]
      mismatches << "transaction_code_mismatch" unless transaction.transaction_code_id == line[:transaction_code]&.id
      mismatches << "misrouted" unless route.success? && transaction.booking_folio_id == route.folio&.id
      mismatches
    end

    def serialize_transaction(transaction)
      {
        "folio_transaction_id" => transaction.id,
        "folio_id" => transaction.booking_folio_id,
        "folio_reference" => transaction.booking_folio.folio_reference_display,
        "amount" => transaction.amount.to_d.to_s("F"),
        "category" => transaction.category,
        "transaction_code_id" => transaction.transaction_code_id,
        "transaction_code_code" => transaction.transaction_code&.code
      }.compact
    end

    def nightly_charge_key(line)
      ChargePostingKeys.nightly_charge_key(
        booking: @booking,
        date: line[:stay_date],
        charge_kind: line[:charge_kind],
        identity: line[:identity]
      )
    end
  end
end
