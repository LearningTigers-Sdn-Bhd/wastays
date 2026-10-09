# frozen_string_literal: true

module StaffAccesses
  class LookupService
    Result = ApplicationResult.define(:user, :outstanding_invitation)

    def initialize(hotel:, email:)
      @hotel = hotel
      @email = email.to_s.strip.downcase
    end

    def call
      return Result.failure("Enter a valid login email.") unless @email.match?(URI::MailTo::EMAIL_REGEXP)

      user = User.find_by(email: @email)
      if user && (user.role != "hotel_staff" || user.account_id != @hotel.account_id)
        return Result.failure("This login cannot be added as staff. Use a separate staff email.")
      end

      access = @hotel.user_hotel_accesses.find_by(user: user) if user
      if access
        message = access.active? ? "This staff member already has access to this property." :
          "This staff member's access was revoked. Restore access through their existing staff row."
        return Result.failure(message)
      end

      Result.success(user: user, outstanding_invitation: @hotel.staff_invitations.unaccepted.exists?(email: @email))
    end
  end
end
