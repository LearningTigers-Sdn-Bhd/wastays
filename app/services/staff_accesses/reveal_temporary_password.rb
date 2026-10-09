# frozen_string_literal: true

module StaffAccesses
  class RevealTemporaryPassword
    Result = ApplicationResult.define(:user)

    def self.available?(access:, hotel:)
      user = access.user
      access.hotel_id == hotel.id && access.active? && user.role == "hotel_staff" &&
        user.account_id == hotel.account_id && user.temporary_password_hotel_id == hotel.id &&
        user.temporary_password.present? && user.authenticate(user.temporary_password).present?
    end

    def self.call(access:, hotel:)
      return Result.failure("Temporary password is unavailable.") unless available?(access: access, hotel: hotel)

      Result.success(user: access.user)
    end
  end
end
