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
        result = Folios::MoveTransaction.call(
          transaction: transaction,
          target_folio: @rule.target_folio,
          user: @actor,
          reason: @reason
        )
        return failure(result.error, moved) unless result.success?

        moved.concat(result.transactions)
      end
      success(moved)
    end

    private

    def success(transactions)
      OpenStruct.new(success?: true, transactions: transactions)
    end

    def failure(message, transactions = [])
      OpenStruct.new(success?: false, error: message, transactions: transactions)
    end
  end
end
