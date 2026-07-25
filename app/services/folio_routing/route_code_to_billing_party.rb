# frozen_string_literal: true


module FolioRouting
  # Kind-agnostic core: ensure an active routing rule sending a transaction code
  # to a target folio (belonging to any bill-to party — company, government,
  # agent, guest), then reconcile forecasts so the charge lands on that folio.
  #
  # Knows nothing about party kinds. Callers resolve the target folio.
  class RouteCodeToBillingParty
    def self.call(booking:, transaction_code:, target_folio:, actor: nil)
      new(booking: booking, transaction_code: transaction_code, target_folio: target_folio, actor: actor).call
    end

    def initialize(booking:, transaction_code:, target_folio:, actor: nil)
      @booking = booking
      @transaction_code = transaction_code
      @target_folio = target_folio
      @actor = actor
    end

    def call
      return failure("A transaction code is required to route charges.") if @transaction_code.blank?
      return failure("A target folio is required to route charges.") if @target_folio.blank?
      return failure("Target folio must be open to receive routed charges.") unless @target_folio.open?

      FolioRoutingRule.transaction do
        rule = @booking.folio_routing_rules.find_or_initialize_by(transaction_code: @transaction_code, active: true)
        rule.assign_attributes(
          hotel: @booking.hotel,
          target_folio: @target_folio,
          created_by: rule.created_by || @actor,
          updated_by: @actor
        )
        rule.save!

        Folios::SyncForecastedCharges.call(booking_folio: @booking.booking_folio || @target_folio)
        success(rule)
      end
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def success(rule) = FolioRouting::RuleResult.success(rule: rule)
    def failure(error) = FolioRouting::RuleResult.failure(error)
  end
end
