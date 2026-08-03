# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Charges::RepairNightlyChargeReconciliation, frozen_time: :business_day do
  let(:business_date) { Date.current }
  let(:hotel) { create(:hotel) }
  let(:actor) { create(:user, account: hotel.account) }
  let(:booking) do
    create(
      :booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 1.day,
      checked_in_at: Time.current
    )
  end
  let!(:room) { create(:booking_room, booking: booking, subtotal: 100) }
  let!(:folio) { create(:booking_folio, booking: booking, hotel: hotel) }
  let(:night_audit) { create(:night_audit, hotel: hotel, business_date: business_date, performed_by_user: actor) }

  before { Financials::EnsureDefaultTransactionCodes.call(hotel) }

  it "posts a missing nightly charge and returns a valid reconciliation" do
    reconciliation = Folios::Charges::NightlyChargeReconciliation.call(
      booking: booking,
      business_date: business_date
    )

    result = described_class.call(
      booking: booking,
      reconciliation: reconciliation,
      actor: actor,
      reason: "Repair missing room charge",
      night_audit: night_audit,
      posting_options: { posting_source: "spec_repair", system_posting: true }
    )

    expect(result).to be_success
    expect(result.reconciliation).to be_valid
    expect(result.reversed_transactions).to be_empty
    expect(result.posted_transactions.sole).to have_attributes(
      booking_folio: folio,
      transaction_type: "charge",
      category: "accommodation",
      amount: 100.to_d
    )
    expect(result.posted_transactions.sole.metadata["posting_source"]).to eq("spec_repair")
  end

  it "does not write when the supplied reconciliation is already valid" do
    reconciliation = Folios::Charges::NightlyChargeReconciliation::Report.new(
      "valid?": true,
      entries: [],
      issues: []
    )

    expect {
      @result = described_class.call(
        booking: booking,
        reconciliation: reconciliation,
        actor: actor,
        reason: "Nothing to repair",
        night_audit: night_audit
      )
    }.not_to change(FolioTransaction, :count)

    expect(@result).to be_success
    expect(@result.reconciliation).to eq(reconciliation)
    expect(@result.posted_transactions).to be_empty
  end
end
