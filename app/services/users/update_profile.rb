# frozen_string_literal: true

module Users
  # Saves a user's own profile. A new password needs the current password
  # first, so someone at an unlocked screen cannot take over the account.
  class UpdateProfile
    def self.call(...) = new(...).call

    def initialize(user:, params:)
      @user = user
      @params = params.to_h.symbolize_keys
    end

    # Returns true when saved. On false, the errors are on the user.
    def call
      current_password = @params.delete(:current_password)
      wrong_password = @params[:password].present? && !@user.authenticate(current_password.to_s)
      @user.assign_attributes(@params)

      if wrong_password
        @user.errors.add(:current_password, "is not correct")
        return false
      end

      @user.save
    end
  end
end
