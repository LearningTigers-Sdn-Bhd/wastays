# frozen_string_literal: true

module CorporateInvitations
  class CreateService
    Result = Struct.new(:success?, :invitation, :error, keyword_init: true)

    def initialize(hotel:, invited_by_user:, attributes:)
      @hotel = hotel
      @invited_by_user = invited_by_user
      @attributes = attributes.to_h.symbolize_keys
    end

    def call
      email = @attributes[:email].to_s.strip.downcase
      return claim_existing_account(email) if @attributes[:hotel_corporate_account_id].present?

      eligibility = CheckEligibility.call(hotel: @hotel, email: email)
      return failure(eligibility.error) unless eligibility.success?

      invitation = nil
      token = nil

      Invitation.transaction do
        invitation = @hotel.corporate_invitations.unaccepted.find_or_initialize_by(email: email)
        token = Invitation.generate_token
        invitation.assign_attributes(invitation_attributes(email, token))
        invitation.save!
      end

      CorporateInvitationMailer.invite(invitation, token).deliver_later
      Result.new(success?: true, invitation: invitation)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence, e.record)
    rescue ActiveRecord::RecordNotUnique
      failure("A pending invitation or corporate relationship already exists.")
    end

    private

    # Invites a contact to an account that already exists. Nothing new is
    # created on acceptance: the person gets a login inside that account, so the
    # bookings already on it are the first thing they see. The account's own
    # terms ride along unchanged, because they are not the invitee's to propose.
    def claim_existing_account(email)
      relationship = @hotel.hotel_corporate_accounts.find_by(id: @attributes[:hotel_corporate_account_id])
      return failure("That account could not be found.") if relationship.nil?
      return failure("This account already has a login. Ask its owner to add colleagues.") unless relationship.unclaimed?
      return failure("Email is required.") if email.blank?
      return failure("This email already belongs to a user. Use a different address for this account.") if User.exists?(email: email)

      invitation = nil
      token = nil
      Invitation.transaction do
        invitation = relationship.claim_invitations.unaccepted.first || relationship.claim_invitations.build(hotel: @hotel)
        token = Invitation.generate_token
        invitation.assign_attributes(claim_attributes(relationship, email, token))
        invitation.save!
      end

      CorporateInvitationMailer.invite(invitation, token).deliver_later
      Result.new(success?: true, invitation: invitation)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence, e.record)
    rescue ActiveRecord::RecordNotUnique
      failure("A pending invitation already exists for this address.")
    end

    def claim_attributes(relationship, email, token)
      {
        account: @hotel.account,
        invited_by_user: @invited_by_user,
        email: email,
        account_type: relationship.account_type,
        relationship_type: relationship.relationship_type,
        credit_limit: relationship.credit_limit,
        credit_currency: relationship.credit_currency,
        payment_terms_days: relationship.payment_terms_days,
        agent_booking_enabled: relationship.agent_booking_enabled,
        agent_payment_hold_hours: relationship.agent_payment_hold_hours,
        token_digest: Invitation.digest(token),
        expires_at: Invitation::EXPIRY.from_now,
        last_sent_at: Time.current
      }
    end

    def invitation_attributes(email, token)
      # A hold only means something for an account that can take rooms, so an
      # invitation that does not grant booking carries no hold either. Storing
      # one anyway would quietly apply it the day booking was switched on.
      booking_enabled = ActiveModel::Type::Boolean.new.cast(@attributes[:agent_booking_enabled]).present?

      {
        account: @hotel.account,
        invited_by_user: @invited_by_user,
        email: email,
        account_type: @attributes[:account_type].presence || "company",
        market: @attributes[:market].presence,
        relationship_type: @attributes[:relationship_type].presence || "standard",
        credit_limit: @attributes[:credit_limit].presence,
        credit_currency: @attributes[:credit_currency].presence || @hotel.default_currency,
        payment_terms_days: @attributes[:payment_terms_days].presence,
        agent_booking_enabled: booking_enabled,
        agent_payment_hold_amount: booking_enabled ? @attributes[:agent_payment_hold_amount] : nil,
        agent_payment_hold_unit: @attributes[:agent_payment_hold_unit],
        token_digest: Invitation.digest(token),
        expires_at: Invitation::EXPIRY.from_now,
        last_sent_at: Time.current
      }
    end

    def failure(message, invitation = nil)
      Result.new(success?: false, invitation: invitation, error: message)
    end
  end
end
