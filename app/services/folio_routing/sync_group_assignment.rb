# frozen_string_literal: true

require "ostruct"

module FolioRouting
  class SyncGroupAssignment
    def self.call(assignment:, transaction_codes:, actor: nil)
      new(assignment: assignment, transaction_codes: transaction_codes, actor: actor).call
    end

    def initialize(assignment:, transaction_codes:, actor: nil)
      @assignment = assignment
      @arrangement = assignment.group_billing_arrangement
      @booking = assignment.booking
      @transaction_codes = Array(transaction_codes).uniq
      @actor = actor
    end

    def call
      folio_result = Billing::EnsureCorporateFolio.call(booking: @booking, arrangement: @arrangement, actor: @actor)
      return failure(folio_result.error) unless folio_result.success?

      rules = []
      FolioRoutingRule.transaction do
        @transaction_codes.each do |code|
          rule = @booking.folio_routing_rules.active.find_or_initialize_by(transaction_code: code)
          rule.assign_attributes(
            hotel: @booking.hotel,
            target_folio: folio_result.folio,
            source_type: "group",
            group_billing_arrangement: @arrangement,
            booking_billing_assignment: @assignment,
            effective_from: @assignment.effective_from,
            effective_until: @assignment.effective_until,
            created_by: rule.created_by || @actor,
            updated_by: @actor
          )
          rule.save!
          rules << rule
        end
      end

      OpenStruct.new(success?: true, rules: rules, folio: folio_result.folio)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def failure(message)
      OpenStruct.new(success?: false, error: message, rules: [], folio: nil)
    end
  end
end
