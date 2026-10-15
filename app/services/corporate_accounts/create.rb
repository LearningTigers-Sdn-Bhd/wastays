# frozen_string_literal: true

module CorporateAccounts
  class Create
    Result = ApplicationResult.define(:relationship, :user, :created)
    RELATIONSHIP_ATTRIBUTES = %i[account_type market relationship_type credit_limit credit_currency
      payment_terms_days agent_booking_enabled agent_payment_hold_amount agent_payment_hold_unit].freeze

    def self.call(...) = new(...).call

    def initialize(hotel:, attributes:)
      @hotel = hotel
      @attributes = attributes.to_h.symbolize_keys
    end

    def call
      @hotel.with_lock do
        lookup = Lookup.call(hotel: @hotel, email: @attributes[:email])
        return Result.failure(lookup.error) unless lookup.success?

        user = lookup.user
        created = user.nil?
        user ||= create_user!
        relationship = @hotel.hotel_corporate_accounts.create!(
          **relationship_attributes, corporate_account: user.account, contact_email: user.email, status: "active"
        )
        Result.success(relationship: relationship, user: user, created: created)
      end
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.to_sentence)
    rescue ActiveRecord::RecordNotUnique
      Result.failure("This email or account is already in use. Continue again to check its current details.")
    end

    private

    def create_user!
      account = Account.create!(name: @attributes[:account_name], slug: unique_slug, account_kind: "corporate", status: "active")
      password = SecureRandom.alphanumeric(16)
      User.create!(account: account, role: "corporate", email: @attributes[:email], name: @attributes[:name],
        password: password, password_confirmation: password,
        temporary_password: password, temporary_password_hotel: @hotel)
    end

    def unique_slug
      base = @attributes[:account_name].to_s.parameterize.presence || "corporate-account"
      slug = base
      suffix = 2
      while Account.exists?(slug: slug)
        slug = "#{base}-#{suffix}"
        suffix += 1
      end
      slug
    end

    def relationship_attributes
      attributes = @attributes.slice(*RELATIONSHIP_ATTRIBUTES)
      attributes[:account_type] = attributes[:account_type].presence || "company"
      attributes[:relationship_type] = attributes[:relationship_type].presence || "direct_bill"
      attributes[:credit_currency] = attributes[:credit_currency].presence || @hotel.default_currency
      attributes[:agent_booking_enabled] = ActiveModel::Type::Boolean.new.cast(attributes[:agent_booking_enabled]) || false
      attributes[:agent_payment_hold_amount] = nil unless attributes[:agent_booking_enabled]
      attributes
    end
  end
end
