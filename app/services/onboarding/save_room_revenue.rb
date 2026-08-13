# frozen_string_literal: true

module Onboarding
  # Room revenue: which taxes a room night carries, and when a later change to
  # those rules should reach bookings that already exist.
  #
  # The code being configured is always ROOM — resolved, never taken from params —
  # and the four stay-event codes inherit its rules, so there is nothing else to
  # edit here. The settings portal wraps this in a blast-radius preview with a
  # freshness token, but that machinery exists for hotels with open folios; a
  # property still in setup has no bookings to disturb, so onboarding takes the
  # direct path.
  #
  # The reservation-policy and transaction-code defaults are created here, on a
  # save the owner initiated, rather than by rendering the page.
  class SaveRoomRevenue
    Result = ApplicationResult.define(:section)

    def initialize(hotel:, actor:, params:, complete:)
      @hotel = hotel
      @actor = actor
      @params = params
      @complete = complete
    end

    def call
      transition_result = nil
      @error = nil

      Hotel.transaction do
        ReservationPolicies::EnsureDefaults.call(@hotel)

        room_revenue_code = TransactionCodes::Resolver.for(@hotel).room_revenue
        if room_revenue_code.blank?
          @error = "Room revenue is not configured for this property yet. Contact support."
          raise ActiveRecord::Rollback
        end

        # ROOM is taxable exactly when it carries rules; there is no separate
        # switch to get out of step with the selection.
        room_revenue_code.update!(is_taxable: tax_rule_keys.any?)
        TransactionCodes::AssignTaxRules.call(transaction_code: room_revenue_code, keys: tax_rule_keys)

        unless save_configuration
          raise ActiveRecord::Rollback
        end

        transition_result = UpdateSection.new(
          hotel: @hotel,
          section_key: "room_revenue",
          state: @complete ? "complete" : "in_progress",
          actor: @actor,
          metadata: {
            source: "room_revenue_setup",
            tax_rule_keys: tax_rule_keys,
            tax_fingerprint: TaxFingerprint.call(@hotel)
          }
        ).call
        raise ActiveRecord::Rollback unless transition_result.success?
      end

      return Result.failure(@error, section: nil) if @error.present?
      return Result.failure(transition_result.error, section: transition_result.section) unless transition_result&.success?

      Result.success(section: transition_result.section)
    rescue ArgumentError => e
      Result.failure(e.message, section: nil)
    end

    private

    def tax_rule_keys
      @tax_rule_keys ||= Array(@params.dig(:transaction_code, :tax_rule_keys)).reject(&:blank?).map(&:to_s).uniq
    end

    def save_configuration
      configuration = @hotel.transaction_configuration
      configuration.room_revenue_tax_rule_application = tax_rule_application
      return true if configuration.save

      @error = configuration.errors.full_messages.to_sentence
      false
    end

    def tax_rule_application
      submitted = @params.dig(:hotel_transaction_configuration, :room_revenue_tax_rule_application).to_s
      return submitted if HotelTransactionConfiguration::ROOM_REVENUE_TAX_RULE_APPLICATIONS.key?(submitted.to_sym)

      @hotel.transaction_configuration.room_revenue_tax_rule_application.presence || "new_bookings_only"
    end
  end
end
