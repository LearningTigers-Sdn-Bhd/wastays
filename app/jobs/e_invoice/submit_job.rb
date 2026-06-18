# frozen_string_literal: true

module EInvoice
  class SubmitJob < ApplicationJob
    queue_as :default

    retry_on MyInvois::Client::ApiError, wait: :polynomially_longer, attempts: 3

    def perform(booking_id)
      booking = Booking.find_by(id: booking_id)
      return unless booking

      EInvoice::Submit.call(booking)
    end
  end
end
