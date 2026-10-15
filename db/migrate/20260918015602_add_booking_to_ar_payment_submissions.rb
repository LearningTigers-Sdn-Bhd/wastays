# frozen_string_literal: true

# A standard (non-direct-bill) agent has no AR invoice to pay against: invoices
# are raised from a closed folio at checkout, so at booking time there is
# nothing for a remittance to allocate to. The agent still has to pay before the
# hold expires, so a submission may instead name the booking it prepays.
#
# A submission therefore settles invoices (allocations) or prepays a booking
# (this column) -- see ArPaymentSubmission#has_a_target.
class AddBookingToArPaymentSubmissions < ActiveRecord::Migration[8.1]
  def change
    add_reference :ar_payment_submissions, :booking, null: true, foreign_key: true, index: true
  end
end
