# frozen_string_literal: true

module Onboarding
  class DeliverInvitationDraft
    Result = ApplicationResult.define(:invitation, :held)

    def self.call(...) = new(...).call

    def initialize(draft:, actor:)
      @draft = draft
      @actor = actor
    end

    def call
      invitation = nil
      token = nil

      @draft.with_lock do
        token = Invitation.generate_token
        invitation = find_or_build_invitation
        assign_invitation(invitation, token)
        invitation.save!
        @draft.update!(invitation:, delivered_at: @draft.delivered_at || Time.current)
      end

      return Result.success(invitation:, held: true) unless @draft.send_invitation?

      deliver_mail(invitation, token)
      invitation.mark_sent!
      Result.success(invitation:, held: false)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.to_sentence, invitation:, held: false)
    rescue ArgumentError => e
      Result.failure(e.message, invitation:, held: false)
    end

    private

    def find_or_build_invitation
      scope = @draft.hotel.invitations.unaccepted
      scope.find_by(email: @draft.email) || invitation_class.new(hotel: @draft.hotel, email: @draft.email)
    end

    def invitation_class
      @draft.is_a?(OnboardingStaffDraft) ? StaffInvitation : CorporateInvitation
    end

    def assign_invitation(invitation, token)
      invitation.assign_attributes(
        account: @draft.hotel.account,
        invited_by_user: @actor,
        token_digest: Invitation.digest(token),
        expires_at: Invitation::EXPIRY.from_now,
        last_sent_at: nil
      )
      if @draft.is_a?(OnboardingStaffDraft)
        invitation.assign_attributes(role: @draft.role, name: @draft.name)
      else
        eligibility = CorporateInvitations::CheckEligibility.call(hotel: @draft.hotel, email: @draft.email)
        raise ArgumentError, eligibility.error unless eligibility.success?
        invitation.assign_attributes(
          account_type: @draft.account_type,
          relationship_type: @draft.relationship_type,
          credit_limit: @draft.credit_limit,
          credit_currency: @draft.credit_currency,
          payment_terms_days: @draft.payment_terms_days
        )
      end
    end

    def deliver_mail(invitation, token)
      if invitation.staff?
        StaffInvitationMailer.invite(invitation, token).deliver_now
      else
        CorporateInvitationMailer.invite(invitation, token).deliver_now
      end
    end
  end
end
