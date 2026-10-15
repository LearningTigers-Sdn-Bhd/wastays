# frozen_string_literal: true

module CorporateAccounts
  class Lookup
    Result = ApplicationResult.define(:user)

    def self.call(hotel:, email:)
      email = email.to_s.strip.downcase
      return Result.failure("Enter a valid login email.") unless email.match?(URI::MailTo::EMAIL_REGEXP)

      eligibility = CorporateInvitations::CheckEligibility.call(hotel: hotel, email: email)
      return Result.failure(eligibility.error) unless eligibility.success?

      user = User.find_by(email: email)
      return Result.failure("This Corporate Account is unavailable.") if user && !user.account&.corporate?

      Result.success(user: user)
    end
  end
end
