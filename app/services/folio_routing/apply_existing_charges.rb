# frozen_string_literal: true

require "ostruct"

module FolioRouting
  class ApplyExistingCharges
    def self.call(rule:, actor:, reason:, confirmation:)
      new(rule: rule, actor: actor, reason: reason, confirmation: confirmation).call
    end

    def initialize(rule:, actor:, reason:, confirmation:)
      @rule = rule
      @actor = actor
      @reason = reason
      @confirmation = confirmation.to_s
    end

    def call
      return failure("Choose existing_and_future or future_only.") unless @confirmation.in?(%w[existing_and_future future_only])
      return success([]) if @confirmation == "future_only"

      moved = []
      preview = FolioRouting::PreviewExistingCharges.call(rule: @rule)
      preview.transactions.each do |transaction|
        result = move_transaction(transaction)
        return failure(result.error, moved) unless result.success?

        moved.concat(result.transactions)
      end
      success(moved)
    end

    private

    def move_transaction(transaction)
      parent_id = transaction.metadata.to_h["parent_folio_transaction_id"].presence ||
        transaction.metadata.to_h[:parent_folio_transaction_id].presence
      if parent_id
        parent = FolioTransaction.find_by(id: parent_id)
        return failure("Attached charge parent is unavailable.") unless parent

        tax_routes = Folios::AttachedTaxTransactions.call(parent).each_with_object({}) do |tax, routes|
          child_rule = @rule.booking.folio_routing_rules.active.find_by(transaction_code_id: tax.transaction_code_id)
          routes[tax.id] = child_rule.target_folio_id if child_rule
        end
        tax_routes[transaction.id] = @rule.target_folio_id
        return Folios::MoveTransaction.call(transaction: parent, target_folio: parent.booking_folio,
          user: @actor, reason: @reason, tax_routes: tax_routes)
      end

      tax_routes = Folios::AttachedTaxTransactions.call(transaction).each_with_object({}) do |tax, routes|
        child_rule = @rule.booking.folio_routing_rules.active.find_by(transaction_code_id: tax.transaction_code_id)
        routes[tax.id] = child_rule.target_folio_id if child_rule
      end
      Folios::MoveTransaction.call(transaction:, target_folio: @rule.target_folio, user: @actor,
        reason: @reason, tax_routes: tax_routes)
    end

    def success(transactions)
      OpenStruct.new(success?: true, transactions: transactions)
    end

    def failure(message, transactions = [])
      OpenStruct.new(success?: false, error: message, transactions: transactions)
    end
  end
end
