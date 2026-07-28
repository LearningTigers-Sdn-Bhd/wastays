# frozen_string_literal: true

module DocumentIdentifiers
  class SyncConfirmationToken
    def self.call!(record:)
      registration = record.booking_confirmation_token
      return RegisterConfirmationToken.call!(record:) unless registration

      registration.update!(token: record.confirmation_token)
    end
  end
end
