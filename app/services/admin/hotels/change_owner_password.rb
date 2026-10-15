# frozen_string_literal: true

module Admin::Hotels
  class ChangeOwnerPassword
    def self.call(user:, password:, password_confirmation:)
      user.with_lock do
        user.errors.clear
        user.errors.add(:password, "must be at least 12 characters") if password.to_s.length < 12
        raise ActiveRecord::RecordInvalid, user if user.errors.any?

        user.update!(password:, password_confirmation:, auth_version: user.auth_version + 1)
        user.owner_password_resets.delete_all
      end
      true
    end
  end
end
