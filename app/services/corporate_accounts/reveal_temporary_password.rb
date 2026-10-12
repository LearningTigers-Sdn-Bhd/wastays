# frozen_string_literal: true

module CorporateAccounts
  class RevealTemporaryPassword
    Result = ApplicationResult.define(:user)

    def self.available?(user:, hotel:)
      user&.corporate? && user.temporary_password_hotel_id == hotel.id && user.temporary_password.present?
    end

    def self.call(relationship:, hotel:)
      return Result.failure("Temporary password is unavailable.") unless relationship.hotel_id == hotel.id

      user = relationship.corporate_account.users.find(&:corporate?)
      return Result.failure("Temporary password is unavailable.") unless available?(user: user, hotel: hotel)
      return Result.failure("Temporary password is unavailable.") unless user.authenticate(user.temporary_password)

      Result.success(user: user)
    end
  end
end
