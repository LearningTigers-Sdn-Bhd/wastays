# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Charges::NightlyChargeReconciliation do
  let(:business_date) { Date.current }
  let(:hotel) { create(:hotel) }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 1.day)
  end
  let!(:room) { create(:booking_room, booking: booking, subtotal: 100.0) }
  let!(:guest_folio) { create(:booking_folio, booking: booking, hotel: hotel) }
  let!(:company_folio) { create(:booking_folio, :secondary, booking: booking, hotel: hotel) }
  let(:room_code) { hotel.transaction_codes.find_by!(system_key: "room_revenue") }

  it "accepts an exact nightly line on its resolved folio" do
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)
    create_nightly_charge(company_folio, 100.0)

    result = described_class.call(booking: booking, business_date: business_date)

    expect(result).to be_valid
    expect(result.issues).to be_empty
  end

  it "reports the expected and actual folios for a misrouted line" do
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)
    transaction = create_nightly_charge(guest_folio, 100.0)

    issue = described_class.call(booking: booking, business_date: business_date).issues.sole

    expect(issue["issue_types"]).to include("misrouted")
    expect(issue["expected_folio_id"]).to eq(company_folio.id)
    expect(issue.dig("actual_transactions", 0, "folio_transaction_id")).to eq(transaction.id)
  end

  def create_nightly_charge(folio, amount)
    key = Folios::Charges::ChargePostingKeys.nightly_charge_key(
      booking: booking,
      date: business_date,
      charge_kind: "accommodation",
      identity: room.id
    )

    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "accommodation",
      amount: amount,
      transaction_code: room_code,
      metadata: {
        nightly_charge_key: key,
        posting_source: "night_audit",
        stay_date: business_date.iso8601
      })
  end
end
