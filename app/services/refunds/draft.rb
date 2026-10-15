# frozen_string_literal: true

module Refunds
  # The request a refund form starts from. After a rejection it comes back
  # with the guest's reason and bank details, so they do not type them again.
  # The amount is left out: the guest names it again.
  class Draft
    CARRIED = %i[reason bank_name account_holder_name account_number account_type].freeze

    def initialize(booking:)
      @booking = booking
    end

    def call
      rejected = @booking.refund_request
      return RefundRequest.new unless rejected&.rejected?

      RefundRequest.new(rejected.slice(*CARRIED))
    end
  end
end
