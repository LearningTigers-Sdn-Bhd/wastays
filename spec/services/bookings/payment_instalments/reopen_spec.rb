# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::PaymentInstalments::Reopen do
  include_context "with a scheduled agent booking"

  let(:new_deadline) { 5.days.from_now }

  before do
    pay(500)
    Bookings::PaymentInstalments::Refund.call(instalment: deposit, user: staff, refund_source: "cash", reason: "Hotel error")
  end

  def reopen(**overrides)
    described_class.call(instalment: deposit.reload, user: staff, due_at: new_deadline, **overrides)
  end

  it "puts the stage back on the agent with the new deadline" do
    result = reopen

    expect(result).to be_success
    expect(deposit.reload).to have_attributes(status: "pending", refunded_at: nil, refund_folio_transaction_id: nil, paid_at: nil)
    expect(deposit.due_at).to be_within(1.second).of(new_deadline)
    expect(deposit.note).to eq("Reopened after a refund (Hotel error)")
    expect(booking.reload.payment_due_at).to be_within(1.second).of(new_deadline)
  end

  it "asks for the deposit again" do
    reopen

    expect(Bookings::PaymentProgress.new(booking.reload).amount_due_now).to eq(500)
  end

  it "keeps what happened in the audit trail" do
    reopen

    log = audit_logs("payment_reopened").last
    expect(log).to have_attributes(user_id: staff.id, category: "financial", source: "agent_payment_panel")
    expect(log.metadata["reason"]).to eq("Previously refunded: Hotel error")
    expect(audit_logs("refund_completed")).to be_present
  end

  it "needs a deadline in the future" do
    expect(reopen(due_at: 1.hour.ago).error).to eq("Choose a deadline in the future.")
    expect(reopen(due_at: nil).error).to eq("Choose a deadline in the future.")
    expect(deposit.reload.status).to eq("refunded")
  end

  it "only reopens a refunded stage" do
    expect(described_class.call(instalment: balance, user: staff, due_at: new_deadline).error).to eq("Only a refunded stage can be reopened.")
  end

  it "refuses on a cancelled booking" do
    booking.update_columns(status: "cancelled")

    expect(reopen.error).to eq("This booking is cancelled, so nothing more is owed on it.")
  end
end
