# frozen_string_literal: true

module CorporateAccounts
  class Update
    Result = ApplicationResult.define(:relationship, :account, :user)

    def self.call(...) = new(...).call

    def initialize(relationship:, relationship_attributes:, account_attributes: {}, user_attributes: {})
      @relationship = relationship
      @account = relationship.corporate_account
      @user = @account.users.find(&:corporate?)
      @relationship_attributes = relationship_attributes
      @account_attributes = account_attributes.to_h.symbolize_keys.slice(:name)
      @user_attributes = user_attributes.to_h.symbolize_keys.slice(:name, :email)
    end

    def call
      Account.transaction do
        @account.lock!
        @user&.lock!
        @relationship.lock!
        @account.assign_attributes(@account_attributes)
        @user&.assign_attributes(@user_attributes)
        @relationship.assign_attributes(@relationship_attributes)

        valid = [ @account, @user, @relationship ].compact.map(&:valid?).all?
        raise ActiveRecord::Rollback unless valid

        @account.save!
        @user&.save!
        @relationship.save!
      end
      records = [ @account, @user, @relationship ].compact
      if records.any? { |record| record.errors.any? }
        failure(records.flat_map { |record| record.errors.full_messages }.to_sentence)
      else
        Result.success(relationship: @relationship, account: @account, user: @user)
      end
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue ActiveRecord::RecordNotUnique
      @user&.errors&.add(:email, "has already been taken")
      failure("This login email is already in use.")
    end

    private

    def failure(error)
      Result.failure(error, relationship: @relationship, account: @account, user: @user)
    end
  end
end
