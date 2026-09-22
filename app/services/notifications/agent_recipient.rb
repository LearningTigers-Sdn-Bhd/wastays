# frozen_string_literal: true

module Notifications
  # Where an agent booking's payment mail goes.
  #
  # The person who made the booking first, because a reminder that the rooms are
  # about to be released is useful to whoever is holding them. The account's
  # contact address is the fallback: bookings made before `corporate_booked_by`
  # was recorded have no person, and a member of staff who has since left the
  # agency should not be the only address on file.
  #
  # Returns nil rather than raising when there is nowhere to write. The caller
  # records a `skipped` delivery, so "were they warned?" still has an answer.
  module AgentRecipient
    module_function

    def email_for(booking)
      booking.corporate_booked_by&.email.presence ||
        booking.hotel_corporate_account&.effective_contact_email.presence
    end

    def name_for(booking)
      booking.corporate_booked_by&.name.presence ||
        booking.hotel_corporate_account&.corporate_account&.name.presence
    end
  end
end
