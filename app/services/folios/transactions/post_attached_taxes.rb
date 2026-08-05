# frozen_string_literal: true

module Folios
  module Transactions
    # Posts the tax lines that hang off a charge.
    #
    # This used to live inside PostStaffTransaction, which meant only staff-posted
    # charges ever grew tax lines. Late-checkout and early-departure charges go
    # through Folios::Charges::PostCategoryCharge instead, and posted untaxed —
    # silently, no matter what the settings page showed.
    #
    # The two codes are separate on purpose. `source_transaction_code` is what the
    # charge posts under (LATE_CO, for GL and reporting); `tax_rule_transaction_code`
    # is whose tax rules apply (ROOM). They are the same code for a staff charge, so
    # that path keeps its exact previous behaviour. For the stay-event codes they
    # differ, which is how "all room revenue is taxed the same way" is enforced in
    # one place rather than four settings screens that can drift apart.
    #
    # Not every room-revenue path belongs here: Bookings::FinalizeNoShow and
    # Folios::Charges::ProcessCatchUpCharges post their own tax lines from the
    # booking's tax snapshot, which is the correct treatment for a historical night.
    # Routing them through this service would double-tax them.
    class PostAttachedTaxes
      Result = ApplicationResult.define(:tax_transactions)

      def self.call(...) = new(...).call

      def initialize(folio:, parent_transaction:, source_transaction_code:, base_amount:, posting_date:, user:,
                     tax_rule_transaction_code: nil, basis: "staff_charge", extra_metadata: {}, options: {})
        @folio = folio
        @parent_transaction = parent_transaction
        @source_transaction_code = source_transaction_code
        @tax_rule_transaction_code = tax_rule_transaction_code || source_transaction_code
        @base_amount = base_amount.to_d.abs
        @posting_date = posting_date
        @user = user
        @basis = basis
        @extra_metadata = extra_metadata
        @options = options
      end

      def call
        return Result.success(tax_transactions: []) unless taxable?

        transactions = []

        active_tax_rules.each do |tax_rule|
          amount = tax_rule.compute(@base_amount).to_d
          next if amount.zero?

          tax_transaction_code = tax_rule.posting_transaction_code
          routing_result = resolve_tax_folio(tax_transaction_code)
          return Result.failure(routing_result.error) unless routing_result.success?

          result = insert_tax_transaction(tax_rule, amount, tax_transaction_code, routing_result)
          return Result.failure(result.error) unless result.success?

          transactions << result.transaction
        end

        Result.success(tax_transactions: transactions.compact)
      end

      private

      def taxable?
        @tax_rule_transaction_code&.is_taxable? && active_tax_rules.any?
      end

      def active_tax_rules
        @active_tax_rules ||= Folios::Routing::EffectiveTaxRules
          .call(booking: @folio.booking, transaction_code: @tax_rule_transaction_code)
          .select(&:enabled_for_posting?)
      end

      def insert_tax_transaction(tax_rule, amount, tax_transaction_code, routing_result)
        Folios::Transactions::InsertTransaction.new(
          booking_folio: routing_result.folio,
          amount: amount,
          transaction_type: "charge",
          category: "tax",
          user: @user,
          description: "Tax: #{tax_rule.display_name} for #{@parent_transaction.description}",
          posting_date: @posting_date,
          options: @options.merge(
            posting_source: posting_source,
            transaction_code: tax_transaction_code,
            parent_transaction: parent_transaction_for_tax_line(routing_result.folio),
            metadata: tax_metadata(tax_rule, amount, routing_result)
          )
        ).call
      end

      def tax_metadata(tax_rule, amount, routing_result)
        (@options[:metadata] || {}).merge(@extra_metadata).merge(
          posting_source: posting_source,
          parent_transaction_id: @parent_transaction.id,
          parent_folio_transaction_id: @parent_transaction.id,
          parent_transaction_code_id: @parent_transaction.transaction_code_id,
          parent_transaction_code_code: @parent_transaction.posted_transaction_code,
          source_transaction_code_id: @source_transaction_code.id,
          source_transaction_code_code: @source_transaction_code.code,
          tax_rule_source_transaction_code_id: @tax_rule_transaction_code.id,
          tax_line: tax_line(tax_rule, amount)
        ).merge(route_metadata(routing_result))
      end

      # A tax line routes to wherever its own code says, when the booking has an
      # active rule for it. Otherwise it follows the charge it belongs to.
      def resolve_tax_folio(tax_transaction_code)
        return parent_tax_route if tax_transaction_code.blank?

        child_rule = @folio.booking.folio_routing_rules.active.find_by(transaction_code: tax_transaction_code)
        return parent_tax_route if child_rule.blank?

        Folios::Routing::ResolveTargetFolio.call(
          booking: @folio.booking,
          transaction_code: tax_transaction_code,
          actor: @user,
          permission_context: permission_context
        )
      end

      def parent_tax_route
        Folios::Routing::ResolveTargetFolio.call(
          booking: @folio.booking,
          transaction_code: @parent_transaction.transaction_code,
          parent_transaction: @parent_transaction,
          actor: @user,
          permission_context: permission_context
        )
      end

      # Only claim parentage when the tax lands on the same folio as its charge;
      # a routed-away tax line has no parent to point at on its own folio.
      def parent_transaction_for_tax_line(target_folio)
        @parent_transaction if @parent_transaction.booking_folio_id == target_folio&.id
      end

      def tax_line(tax_rule, amount)
        posting_transaction_code = tax_rule.posting_transaction_code
        {
          tax_id: tax_rule.hotel_tax_id,
          primary_tax_key: tax_rule.primary_tax_key,
          name: tax_rule.display_name,
          type: tax_rule.tax_line_type,
          transaction_code_id: posting_transaction_code&.id,
          transaction_code_code: posting_transaction_code&.code,
          source_transaction_code_id: @source_transaction_code.id,
          source_transaction_code_code: @source_transaction_code.code,
          rate_type: tax_rule.rate_type,
          rate: tax_rule.amount.to_d.to_s("F"),
          basis: @basis,
          basis_amount: @base_amount.to_s("F"),
          amount: amount.to_s("F"),
          source: "transaction_code_tax_rule"
        }
      end

      def route_metadata(routing_result)
        return {} if routing_result.route_source.blank?

        { route_source: routing_result.route_source, route_metadata: routing_result.route_metadata }
      end

      def posting_source
        @options[:posting_source].presence || "staff"
      end

      def permission_context
        @options[:permission_context] || @user
      end
    end
  end
end
