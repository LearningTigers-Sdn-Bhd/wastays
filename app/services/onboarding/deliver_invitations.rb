# frozen_string_literal: true

module Onboarding
  # Turns the staff and corporate drafts collected during setup into real
  # invitations, once, after the property has been submitted.
  #
  # Every draft becomes an invitation. Only the drafts whose owner switched
  # "Send invitation" on are emailed; the rest are created unsent, so they appear
  # on Staff Management and Corporate Accounts as people the property has listed
  # but not yet contacted. `Invitation#last_sent_at` is what tells those two
  # states apart, and the seven-day expiry only starts meaning something once it
  # is stamped.
  #
  # Delivery is resumable rather than all-or-nothing. Each draft is its own
  # transaction and is marked the moment it succeeds, so a run that dies halfway
  # can be repeated without inviting the first half a second time. Drafts that
  # already carry an invitation are skipped outright.
  #
  # Mail is never sent inside a transaction — `deliver_later` enqueues, and an
  # enqueue that survives a rolled-back draft would be an email about a record
  # that does not exist.
  class DeliverInvitations
    Result = ApplicationResult.define(:sent_count, :held_count, :failures)

    def self.call(...) = new(...).call

    def initialize(hotel:, actor:)
      @hotel = hotel
      @actor = actor
      @sent = 0
      @held = 0
      @failures = []
    end

    def call
      hotel.onboarding_staff_drafts.undelivered.includes(:role).each { |draft| deliver_staff(draft) }
      hotel.onboarding_corporate_drafts.undelivered.each { |draft| deliver_corporate(draft) }

      Result.success(sent_count: @sent, held_count: @held, failures: @failures)
    end

    private

    attr_reader :hotel, :actor

    def deliver_staff(draft)
      token = Invitation.generate_token
      invitation = hotel.staff_invitations.unaccepted.find_or_initialize_by(email: draft.email)
      invitation.assign_attributes(
        account: hotel.account,
        role: draft.role,
        name: draft.name,
        invited_by_user: actor,
        token_digest: Invitation.digest(token),
        expires_at: Invitation::EXPIRY.from_now,
        last_sent_at: (Time.current if draft.send_invitation)
      )

      deliver(draft, invitation) do
        StaffInvitationMailer.invite(invitation, token).deliver_later
      end
    end

    def deliver_corporate(draft)
      eligibility = CorporateInvitations::CheckEligibility.call(hotel: hotel, email: draft.email)
      return record_failure(draft, eligibility.error) unless eligibility.success?

      token = Invitation.generate_token
      invitation = hotel.corporate_invitations.unaccepted.find_or_initialize_by(email: draft.email)
      invitation.assign_attributes(
        account: hotel.account,
        invited_by_user: actor,
        account_type: draft.account_type,
        relationship_type: draft.relationship_type,
        credit_limit: draft.credit_limit,
        credit_currency: draft.credit_currency,
        payment_terms_days: draft.payment_terms_days,
        token_digest: Invitation.digest(token),
        expires_at: Invitation::EXPIRY.from_now,
        last_sent_at: (Time.current if draft.send_invitation)
      )

      deliver(draft, invitation) do
        CorporateInvitationMailer.invite(invitation, token).deliver_later
      end
    end

    # The draft is marked in the same transaction that creates the invitation.
    # Marking afterwards would leave a window where a retry sends a second one.
    def deliver(draft, invitation)
      Invitation.transaction do
        invitation.save!
        draft.update!(invitation: invitation, delivered_at: Time.current)
      end

      if draft.send_invitation
        yield
        @sent += 1
      else
        @held += 1
      end
    rescue ActiveRecord::RecordInvalid => e
      record_failure(draft, e.record.errors.full_messages.to_sentence)
    end

    def record_failure(draft, message)
      @failures << { email: draft.email, error: message }
    end
  end
end
