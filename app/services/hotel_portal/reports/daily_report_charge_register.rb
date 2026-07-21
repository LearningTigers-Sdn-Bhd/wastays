# frozen_string_literal: true

require "set"

module HotelPortal
  module Reports
    class DailyReportChargeRegister
      Result = Data.define(:rows, :amount_total, :tax_total)

      class ExpectedTaxCodeResolver
        def initialize(transactions:)
          @transactions = transactions
        end

        def call
          pairs = booking_code_pairs
          return {} if pairs.empty?

          defaults = default_rules(pairs)
          overrides = booking_overrides(pairs)
          hotel_tax_ids = (tax_ids(defaults) + tax_ids(overrides)).uniq
          hotel_taxes = custom_tax_details(hotel_tax_ids)
          hotels = hotel_details(pairs.values.uniq)
          primary_codes = primary_transaction_codes(pairs.values.uniq)

          pairs.to_h do |pair, hotel_id|
            rules = defaults.fetch(pair.last, {}).dup
            overrides.fetch(pair, []).each do |action, primary_tax_key, hotel_tax_id|
              key = tax_key(primary_tax_key, hotel_tax_id)
              if action == "exclude"
                rules.delete(key)
              else
                rules[key] ||= [ primary_tax_key, hotel_tax_id ]
              end
            end

            expected_ids = rules.values.filter_map do |primary_tax_key, hotel_tax_id|
              if primary_tax_key
                next unless primary_tax_enabled?(hotels[hotel_id], primary_tax_key)

                primary_codes[[ hotel_id, primary_tax_key ]]
              else
                enabled, transaction_code_id = hotel_taxes[hotel_tax_id]
                transaction_code_id if enabled
              end
            end.uniq

            [ pair, expected_ids ]
          end
        end

        private

        def booking_code_pairs
          @transactions.each_with_object({}) do |transaction, pairs|
            next if transaction.transaction_code_id.blank?

            folio = transaction.booking_folio
            pairs[[ folio.booking_id, transaction.transaction_code_id ]] ||= folio.hotel_id
          end
        end

        def default_rules(pairs)
          TransactionCodeTax.where(transaction_code_id: pairs.keys.map(&:last).uniq)
            .pluck(:transaction_code_id, :primary_tax_key, :hotel_tax_id)
            .each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |(code_id, primary_tax_key, hotel_tax_id), rules|
              rules[code_id][tax_key(primary_tax_key, hotel_tax_id)] = [ primary_tax_key, hotel_tax_id ]
            end
        end

        def booking_overrides(pairs)
          BookingTaxInclusionOverride
            .where(booking_id: pairs.keys.map(&:first).uniq, transaction_code_id: pairs.keys.map(&:last).uniq)
            .pluck(:booking_id, :transaction_code_id, :action, :primary_tax_key, :hotel_tax_id)
            .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |row, overrides|
              booking_id, transaction_code_id, action, primary_tax_key, hotel_tax_id = row
              pair = [ booking_id, transaction_code_id ]
              next unless pairs.key?(pair)

              overrides[pair] << [ action, primary_tax_key, hotel_tax_id ]
            end
        end

        def custom_tax_details(hotel_tax_ids)
          HotelTax.where(id: hotel_tax_ids).pluck(:id, :enabled, :transaction_code_id).to_h do |id, enabled, code_id|
            [ id, [ enabled, code_id ] ]
          end
        end

        def hotel_details(hotel_ids)
          Hotel.where(id: hotel_ids).pluck(:id, :sst_enabled, :tourism_tax_enabled).to_h do |id, sst_enabled, tourism_tax_enabled|
            [ id, { "sst_tax" => sst_enabled, "tourism_tax" => tourism_tax_enabled } ]
          end
        end

        def primary_transaction_codes(hotel_ids)
          TransactionCode.where(hotel_id: hotel_ids, system_key: TransactionCodeTax::PRIMARY_TAX_KEYS)
            .pluck(:hotel_id, :system_key, :id)
            .to_h { |hotel_id, system_key, id| [ [ hotel_id, system_key ], id ] }
        end

        def tax_ids(rule_sets)
          rule_sets.values.flat_map do |rules|
            values = rules.is_a?(Hash) ? rules.values : rules
            values.filter_map { |rule| rule.last }
          end
        end

        def tax_key(primary_tax_key, hotel_tax_id)
          primary_tax_key ? "primary:#{primary_tax_key}" : "hotel_tax:#{hotel_tax_id}"
        end

        def primary_tax_enabled?(hotel, primary_tax_key)
          hotel&.fetch(primary_tax_key, false)
        end
      end

      class Row
        attr_reader :transactions, :tax_transactions, :presentation

        delegate :posting_date, :posted_at, :transaction_time, :transaction_code, :service_name,
          :transaction_type, :category, :description, :booking_reference,
          :folio_number, :guest_name, :room_number, :room_type_name, :room_details, :payment_method,
          :posting_source, :actor_name, :stay_date, :relationship_status,
          :related_transaction_id, :currency, :booking, :folio,
          to: :presentation

        def initialize(transactions:, tax_transactions:)
          @transactions = transactions.freeze
          @tax_transactions = tax_transactions.freeze
          @presentation = DailyReportTransactionRow.new(transactions.first)
          freeze
        end

        def signed_amount
          transactions.sum { |transaction| transaction.amount.to_d }
        end

        def tax_amount
          tax_transactions.sum { |transaction| transaction.amount.to_d }
        end

        def total_amount
          signed_amount + tax_amount
        end

        def transaction_ids
          transactions.map(&:id)
        end

        def tax_transaction_ids
          tax_transactions.map(&:id)
        end
      end

      def initialize(transactions:)
        @transactions = transactions.to_a
      end

      def call
        taxes, visible = @transactions.partition { |transaction| tax_transaction?(transaction) }
        groups = visible.group_by { |transaction| group_key(transaction) }
        @expected_tax_code_ids = ExpectedTaxCodeResolver.new(transactions: visible).call
        tax_assignments = Hash.new { |hash, key| hash[key] = [] }
        claimed_tax_ids = Set.new
        transaction_group_keys = groups.each_with_object({}) do |(key, transactions), index|
          transactions.each { |transaction| index[transaction.id] = key }
        end

        taxes.each do |tax|
          next if claimed_tax_ids.include?(tax.id)

          parent_id = parent_transaction_id(tax)
          key = transaction_group_keys[parent_id]
          next unless key

          tax_assignments[key] << tax
          claimed_tax_ids << tax.id
        end

        taxes.each do |tax|
          next if claimed_tax_ids.include?(tax.id) || parent_transaction_id(tax).present?

          key = inferred_group_key(tax, groups)
          next unless key

          tax_assignments[key] << tax
          claimed_tax_ids << tax.id
        end

        rows = groups.map do |key, grouped_transactions|
          Row.new(transactions: grouped_transactions, tax_transactions: tax_assignments[key])
        end.freeze

        Result.new(
          rows: rows,
          amount_total: rows.sum(&:signed_amount),
          tax_total: rows.sum(&:tax_amount)
        )
      end

      private

      def tax_transaction?(transaction)
        transaction.transaction_type == "charge" &&
          (transaction.category == "tax" || transaction.metadata.to_h["tax_line"].present?)
      end

      def group_key(transaction)
        return [ :adjustment, transaction.id ] if transaction.transaction_type == "adjustment"

        presentation = DailyReportTransactionRow.new(transaction)
        [
          :charge,
          transaction.booking_folio.booking_id,
          effective_date(transaction),
          transaction.transaction_code_id,
          transaction.category,
          presentation.relationship_status
        ]
      end

      def parent_transaction_id(transaction)
        metadata = transaction.metadata.to_h
        (metadata["parent_folio_transaction_id"].presence || metadata[:parent_folio_transaction_id].presence)&.to_i
      end

      def inferred_group_key(tax, groups)
        candidates = groups.select do |_key, transactions|
          representative = transactions.first
          representative.transaction_type == "charge" &&
            representative.booking_folio.booking_id == tax.booking_folio.booking_id &&
            effective_date(representative) == effective_date(tax)
        end

        source_code_id = source_transaction_code_id(tax)
        fallback_key = candidates.keys.first if source_code_id.blank? && candidates.keys.one?
        if source_code_id.blank?
          taxable_candidates = candidates.select do |_key, transactions|
            transactions.first.transaction_code&.is_taxable?
          end
          fallback_key = taxable_candidates.keys.first if taxable_candidates.keys.one?
        end
        if source_code_id
          candidates.select! do |_key, transactions|
            transactions.first.transaction_code_id == source_code_id
          end
        else
          candidates.select! do |_key, transactions|
            expected_tax_code_ids(transactions.first).include?(tax.transaction_code_id)
          end
        end

        return candidates.keys.first if candidates.keys.one?

        candidates.empty? ? fallback_key : nil
      end

      def effective_date(transaction)
        metadata = transaction.metadata.to_h
        metadata["stay_date"].presence || metadata[:stay_date].presence || transaction.posting_date.iso8601
      end

      def source_transaction_code_id(transaction)
        metadata = transaction.metadata.to_h.with_indifferent_access
        tax_line = metadata[:tax_line].to_h.with_indifferent_access
        (tax_line[:source_transaction_code_id].presence || metadata[:source_transaction_code_id].presence)&.to_i
      end

      def expected_tax_code_ids(transaction)
        return [] if transaction.transaction_code.blank?

        key = [ transaction.booking_folio.booking_id, transaction.transaction_code_id ]
        @expected_tax_code_ids.fetch(key, [])
      end
    end
  end
end
