# frozen_string_literal: true

module Bookings
  # Marks the stages a booking's payments now cover as paid, in order, and moves
  # the booking's deadline on to the next stage still owed.
  #
  # Run after a payment reaches the folio. It reads the folio rather than the
  # amount just posted, so it settles correctly however the money arrived: a
  # deposit, the whole amount at once, or a top-up that only partly covers the
  # next stage. Stopping at the first stage that is not covered keeps a later
  # stage from being marked paid ahead of an earlier one.
  class SettlePaymentInstalments
    def self.call(...) = new(...).call

    def initialize(booking:, folio_transaction: nil, user: nil, now: Time.current)
      @booking = booking
      @folio_transaction = folio_transaction
      @user = user
      @now = now
    end

    def call
      progress = PaymentProgress.new(@booking)

      progress.instalments.select(&:status_pending?).each do |instalment|
        break unless progress.covers?(instalment)

        instalment.update!(
          status: "paid", paid_at: @now, paid_by: @user, payment_folio_transaction: @folio_transaction
        )
      end

      SyncPaymentDeadline.call(@booking)
    end
  end
end
