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
      true
    rescue StandardError => e
      false
    end
  end
end
