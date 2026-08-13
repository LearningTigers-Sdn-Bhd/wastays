# frozen_string_literal: true

module StaffInvitations
  class ResendService
    def initialize(invitation, user)
      @invitation = invitation
      @user = user
    end

    def call
      token = @invitation.refresh!(role: @invitation.role, invited_by_user: @user)
      StaffInvitationMailer.invite(@invitation, token).deliver_later
      # Also the first send for an invitation queued during onboarding with the
      # switch off, which is why this stamps rather than assumes a prior send.
      @invitation.mark_sent!
      true
    rescue StandardError => e
      false
    end
  end
end
