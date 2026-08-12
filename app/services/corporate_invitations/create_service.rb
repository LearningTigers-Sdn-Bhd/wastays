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

    def invitation_attributes(email, token)
      {
        account: @hotel.account,
        invited_by_user: @invited_by_user,
        email: email,
        account_type: @attributes[:account_type].presence || "company",
        relationship_type: @attributes[:relationship_type].presence || "standard",
        credit_limit: @attributes[:credit_limit].presence,
        credit_currency: @attributes[:credit_currency].presence || @hotel.default_currency,
        payment_terms_days: @attributes[:payment_terms_days].presence,
        token_digest: Invitation.digest(token),
        expires_at: Invitation::EXPIRY.from_now
      }
    end

    def failure(message, invitation = nil)
      Result.new(success?: false, invitation: invitation, error: message)
    end
  end
end
