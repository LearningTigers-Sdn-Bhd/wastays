# frozen_string_literal: true

module CorporateInvitations
  class AcceptService
    Result = Struct.new(:success?, :user, :relationship, :error, keyword_init: true)

    def initialize(invitation:, user_attributes: {}, accepting_user: nil)
      @invitation = invitation
      @user_attributes = user_attributes.to_h.symbolize_keys
      @accepting_user = accepting_user
    end

    def call
      result = nil

      Invitation.transaction do
        @invitation.lock!
        raise ActiveRecord::RecordInvalid, @invitation unless @invitation.pending?

        user = User.find_by(email: @invitation.email)
        validate_existing_user!(user)
        user ||= create_corporate_user!

        existing_relationship = @invitation.hotel.hotel_corporate_accounts.find_by(corporate_account: user.account)
        if existing_relationship
          message = existing_relationship.suspended? ?
            "This corporate relationship is suspended. Ask the hotel to reactivate it." :
            "This Corporate Account is already linked to the hotel."
          raise AcceptanceError, message
        end

        relationship = @invitation.hotel.hotel_corporate_accounts.create!(
          corporate_account: user.account,
          account_type: @invitation.account_type,
          relationship_type: @invitation.relationship_type,
          direct_bill_enabled: @invitation.direct_bill_enabled,
          credit_limit: @invitation.credit_limit,
          credit_currency: @invitation.credit_currency,
          payment_terms_days: @invitation.payment_terms_days,
          status: "active"
        )
        @invitation.update!(accepted_at: Time.current)
        result = Result.new(success?: true, user: user, relationship: relationship)
      end

      result
    rescue AcceptanceError => e
      failure(e.message)
    rescue ActiveRecord::RecordInvalid => e
      message = e.record == @invitation && !@invitation.pending? ?
        "This invitation is invalid or has expired." :
        e.record.errors.full_messages.to_sentence
      failure(message)
    rescue ActiveRecord::RecordNotUnique
      failure("This Corporate Account is already linked to the hotel.")
    end

    private

    class AcceptanceError < StandardError; end

    def validate_existing_user!(user)
      return unless user
      raise AcceptanceError, "This email belongs to a hotel staff account. Use a separate corporate email." unless user.corporate?
      raise AcceptanceError, "The Corporate Account is unavailable." unless user.account&.corporate?
      raise AcceptanceError, "The Corporate Account is suspended." if user.account.status == "suspended"
      raise AcceptanceError, "Log in as #{user.email} to accept this invitation." unless @accepting_user == user
    end

    def create_corporate_user!
      account = Account.create!(
        name: @user_attributes[:account_name],
        slug: unique_account_slug(@user_attributes[:account_name]),
        status: "active",
        account_kind: "corporate"
      )

      User.create!(
        account: account,
        role: "corporate",
        email: @invitation.email,
        name: @user_attributes[:name],
        password: @user_attributes[:password],
        password_confirmation: @user_attributes[:password_confirmation]
      )
    end

    def unique_account_slug(name)
      base = name.to_s.parameterize.presence || "corporate-account"
      slug = base
      suffix = 2

      while Account.exists?(slug: slug)
        slug = "#{base}-#{suffix}"
        suffix += 1
      end

      slug
    end

    def failure(message)
      Result.new(success?: false, error: message)
    end
  end
end
