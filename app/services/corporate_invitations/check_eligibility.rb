# frozen_string_literal: true

module CorporateInvitations
  # Whether this property can invite this address as a corporate account.
  #
  # Extracted from CreateService so onboarding can refuse a queued draft at the
  # point the owner types it, rather than letting submission discover the same
  # problem days later when nobody is watching.
  class CheckEligibility
    Result = ApplicationResult.define

    def self.call(...) = new(...).call

    def initialize(hotel:, email:)
      @hotel = hotel
      @email = email.to_s.strip.downcase
    end

    def call
      return Result.failure("Email is required.") if @email.blank?

      user = User.find_by(email: @email)
      return Result.success if user.blank?

      return Result.failure("This email belongs to a hotel staff account. Use a separate corporate email.") unless user.corporate?
      return Result.failure("This Corporate Account is suspended.") if user.account&.status == "suspended"

      relationship = @hotel.hotel_corporate_accounts.find_by(corporate_account: user.account)
      return Result.failure("This Corporate Account is already linked to this hotel.") if relationship&.active?
      return Result.failure("This corporate relationship is suspended. Reactivate it instead of sending a new invitation.") if relationship&.suspended?

      Result.success
    end
  end
end
