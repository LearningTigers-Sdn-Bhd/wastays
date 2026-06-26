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
      true
    rescue ActiveRecord::RecordInvalid
      false
    end
  end
end
