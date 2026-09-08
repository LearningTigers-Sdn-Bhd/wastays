# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # Payment and Deposits: when a guest pays, what the hotel holds, and how it
    # gives the hold back. Words only. An amount the system charges belongs in
    # the payment settings that charge it.
    class PolicyPaymentsController < HotelPortal::GuestContent::PolicyDocumentsController
      self.policy_key = "payment_and_deposits"
      self.document_title = "Payment and Deposits"
      self.notice = "Payment and deposit terms saved."

      private

      def policy_path
        hotel_policy_payments_path(@hotel)
      end
    end
  end
end
