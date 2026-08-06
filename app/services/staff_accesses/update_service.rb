# frozen_string_literal: true

module StaffAccesses
  # Applies a role change, an access status change, or both.
  #
  # Callers pass only what they are changing: the listing row toggles status, the
  # edit sheet sets the role. Either path can lock the property out of its own
  # account, so both invariants live here rather than beside one caller.
  #
  # `role` is trusted — assignability is an authorization question answered by
  # the controller, so nil here means "leave the role alone", never "refused".
  class UpdateService
    Result = ApplicationResult.define(:access)

    def initialize(access:, current_user:, role: nil, active: nil)
      @access = access
      @current_user = current_user
      @role = role
      @active = active
    end

    def call
      if (message = rejection)
        return Result.failure(message, access: @access)
      end

      @access.role = @role if @role.present?
      @access.deactivated_at = @active ? nil : Time.current unless @active.nil?

      unless @access.save
        return Result.failure(@access.errors.full_messages.to_sentence, access: @access)
      end

      Result.success(access: @access)
    end

    private

    def rejection
      return "You cannot change your own access." if own_access?
      return lockout_message if lockout?

      nil
    end

    def own_access?
      @access.user_id == @current_user.id
    end

    # Demoting the sole account manager locks the property out just as surely as
    # revoking them, so a role without account management counts too.
    def lockout?
      return false unless @access.sole_account_manager?

      revoking? || demoting?
    end

    def revoking? = @active == false

    def demoting?
      @role.present? && @role.permissions.none? { |permission|
        permission.slug == UserHotelAccess::ACCOUNT_MANAGEMENT_PERMISSION
      }
    end

    def lockout_message
      "#{@access.user.name} is the only person who can manage this account. " \
        "Give someone else account management first."
    end
  end
end
