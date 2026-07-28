# frozen_string_literal: true

module DocumentIdentifiers
  class RegisterConfirmationToken
    def self.call!(record:)
      owner = record.is_a?(GroupBooking) ? { group_booking: record } : { booking: record }
      BookingConfirmationToken.create!(owner.merge(token: record.confirmation_token))
    rescue ActiveRecord::RecordNotUnique
      raise if BookingConfirmationToken.exists?(owner)

      record.update_column(:confirmation_token, HotelReferences.generate_confirmation_token)
      retry
    end
  end
end
