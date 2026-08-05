# frozen_string_literal: true

module StaffInvitations
  # Issues (or refreshes) a staff invitation for one email on one property.
  #
  # Always answers with an invitation — persisted on success, in-memory with
  # errors attached on failure — so the sheet can re-render the operator's input
  # instead of bouncing them back to the list.
  class CreateService
    Result = ApplicationResult.define(:invitation)

    def initialize(hotel:, invited_by:, email:, role:)
      @hotel = hotel
      @invited_by = invited_by
      @email = email.to_s.strip.downcase
      @role = role
    end

    def call
      invitation = build_invitation

      if (message = rejection)
        invitation.errors.add(:base, message)
        return Result.failure(message, invitation: invitation)
      end

      token = StaffInvitation.generate_token
      invitation.assign_attributes(
        account: @hotel.account,
        role: @role,
        invited_by_user: @invited_by,
        token_digest: StaffInvitation.digest(token),
        expires_at: StaffInvitation::EXPIRY.from_now
      )

      unless invitation.save
        return Result.failure(invitation.errors.full_messages.to_sentence, invitation: invitation)
      end

      StaffInvitationMailer.invite(invitation, token).deliver_later
      Result.success(invitation: invitation)
    end

    private

    # Reuses the outstanding invitation for this email so a re-invite refreshes
    # the token and expiry rather than stacking duplicates.
    def build_invitation
      invitation = @hotel.staff_invitations.find_or_initialize_by(email: @email, accepted_at: nil)
      invitation.role = @role
      invitation
    end

    def rejection
      return "Email and role are required." if @email.blank? || @role.blank?
      return "This email belongs to a corporate account. Use a separate staff email." if invitee&.corporate?
      return "This user already has active access to this property." if already_has_access?

      nil
    end

    def invitee
      return @invitee if defined?(@invitee)

      @invitee = User.find_by(email: @email)
    end

    def already_has_access?
      invitee.present? && @hotel.user_hotel_accesses.active.exists?(user: invitee)
    end
  end
end
