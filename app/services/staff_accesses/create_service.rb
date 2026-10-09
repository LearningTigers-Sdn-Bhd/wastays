# frozen_string_literal: true

module StaffAccesses
  class CreateService
    Result = ApplicationResult.define(:user, :access, :created)

    def initialize(hotel:, email:, name:, role:)
      @hotel = hotel
      @email = email.to_s.strip.downcase
      @name = name
      @role = role
    end

    def call
      return Result.failure("Select a role for this property.") unless @role && @role.account_id == @hotel.account_id

      @hotel.with_lock do
        # Acceptance locks the invitation before creating a login or access.
        # Lock these rows first so replacement cannot race with acceptance.
        invitations = @hotel.staff_invitations.unaccepted.where(email: @email).order(:id).lock.to_a
        lookup = LookupService.new(hotel: @hotel, email: @email).call
        return Result.failure(lookup.error) unless lookup.success?

        user = lookup.user
        created = user.nil?
        user ||= create_user!
        access = @hotel.user_hotel_accesses.create!(user: user, role: @role)
        invitations.each(&:destroy!)

        Result.success(user: user, access: access, created: created)
      end
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.to_sentence)
    rescue ActiveRecord::RecordNotUnique
      Result.failure("This email is already in use. Continue again to check its current details.")
    end

    private

    def create_user!
      password = SecureRandom.alphanumeric(16)
      User.create!(account: @hotel.account, role: "hotel_staff", email: @email, name: @name,
        password: password, password_confirmation: password,
        temporary_password: password, temporary_password_hotel: @hotel)
    end
  end
end
