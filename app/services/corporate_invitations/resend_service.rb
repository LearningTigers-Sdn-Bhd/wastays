# frozen_string_literal: true

module CorporateInvitations
  class ResendService
    def initialize(invitation:, invited_by_user:)
      @invitation = invitation
      @invited_by_user = invited_by_user
    end

    def call
      return false if @invitation.accepted?

      token = @invitation.refresh!(invited_by_user: @invited_by_user)
      CorporateInvitationMailer.invite(@invitation, token).deliver_later
      # Also the first send for an invitation queued during onboarding with the
      # switch off, which is why this stamps rather than assumes a prior send.
      @invitation.mark_sent!
      true
    rescue ActiveRecord::RecordInvalid
      false
    end
  end
end
