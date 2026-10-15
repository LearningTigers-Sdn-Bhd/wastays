# frozen_string_literal: true

# A standard agent booking of 1000 with its deposit (500) and balance (500)
# scheduled, and a folio to post against. `pay` posts a payment the way the desk
# does, which is enough to settle stages.
RSpec.shared_context "with a scheduled agent booking" do
  let(:hotel) { create(:hotel, status: "live", agent_payment_hold_hours: 72) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent") }
  let(:staff) { create(:user) }
  let(:booking) do
    create(:booking, hotel: hotel, hotel_corporate_account: relationship, status: "confirmed", payment_status: "pending",
                     total_amount: 1000, currency: "MYR", check_in: 60.days.from_now, check_out: 62.days.from_now)
  end
  let!(:folio) { create(:booking_folio, booking: booking, hotel: hotel, currency: "MYR") }
  let(:deposit) { booking.payment_instalments.find_by!(kind: "deposit") }
  let(:balance) { booking.payment_instalments.find_by!(kind: "balance") }

  before { Bookings::CreatePaymentSchedule.call(booking: booking) }

  def pay(amount)
    result = Folios::Transactions::InsertTransaction.new(
      booking_folio: folio, amount: amount, transaction_type: "payment", category: "booking_payment",
      user: staff, description: "test payment", options: { system_posting: true, posting_source: "spec" }
    ).call
    raise result.error unless result.success?

    booking.reload
  end

  def audit_logs(action_type)
    BookingAuditLog.where(auditable: booking, action_type: action_type)
  end
end
