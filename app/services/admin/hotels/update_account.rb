# frozen_string_literal: true

module Admin::Hotels
  class UpdateAccount
    def self.call(hotel:, owner:, account_name:, owner_name:, owner_email:)
      ActiveRecord::Base.transaction do
        hotel.account.update!(name: account_name)
        if owner
          owner.update!(name: owner_name, email: owner_email)
          owner.owner_password_resets.delete_all if owner.saved_change_to_email?
        end
      end
      true
    end
  end
end
