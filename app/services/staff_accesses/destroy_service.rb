# frozen_string_literal: true

module StaffAccesses
  # Permanently removes a staff member's access row.
  #
  # Deliberately narrow: it deletes the UserHotelAccess only, never the User.
  # Users are referenced by night audits and by invitations they sent, so
  # deleting one either fails outright or silently orphans that history.
  class DestroyService
    Result = ApplicationResult.define(:access)

    def initialize(access:, current_user:)
      @access = access
      @current_user = current_user
    end

    def call
      if (message = rejection)
        return Result.failure(message, access: @access)
      end

      @access.destroy!
      Result.success(access: @access)
    end

    private

    def rejection
      return "You cannot delete your own access." if @access.user_id == @current_user.id
      return lockout_message if @access.sole_account_manager?

      nil
    end

    def lockout_message
      "#{@access.user.name} is the only person who can manage this account. " \
        "Give someone else account management first."
    end
  end
end
