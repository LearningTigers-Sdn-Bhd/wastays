# frozen_string_literal: true

module ArInvoices
  class AuthorizeCreditExposure
    include Authorizable

    PERMISSION = "override_corporate_credit_limit"
    Result = ApplicationResult.define(:exposure, :"override_used?", :override_reason)

    def self.call(hotel_corporate_account:, pending_amount:, pending_currency:, user:, override: false, override_reason: nil)
      new(
        hotel_corporate_account: hotel_corporate_account,
        pending_amount: pending_amount,
        pending_currency: pending_currency,
        user: user,
        override: override,
        override_reason: override_reason
      ).call
    end

    def initialize(hotel_corporate_account:, pending_amount:, pending_currency:, user:, override:, override_reason:)
      @hotel_corporate_account = hotel_corporate_account
      @pending_amount = pending_amount
      @pending_currency = pending_currency
      @user = user
      @override = ActiveModel::Type::Boolean.new.cast(override)
      @override_reason = override_reason.to_s.strip
    end

    def call
      return Result.success(exposure: exposure, "override_used?": false, override_reason: nil) unless exposure.requires_override?
      return Result.failure(required_override_message, exposure: exposure) unless @override
      return Result.failure("Corporate credit override reason can't be blank.", exposure: exposure) if @override_reason.blank?
      return Result.failure("You do not have permission to override the corporate credit limit.", exposure: exposure) unless override_permitted?

      Result.success(exposure: exposure, "override_used?": true, override_reason: @override_reason)
    end

    private

    def exposure
      @exposure ||= CreditExposure.call(
        hotel_corporate_account: @hotel_corporate_account,
        pending_amount: @pending_amount,
        pending_currency: @pending_currency
      )
    end

    def required_override_message
      return "Corporate credit exposure uses currencies that cannot be compared. An explicit override is required." if exposure.currency_mismatch?

      "Corporate credit limit exceeded. An explicit override is required."
    end

    def override_permitted?
      actor_permits?(@user, PERMISSION, hotel: @hotel_corporate_account.hotel)
    end
  end
end
