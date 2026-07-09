# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingBillingParties::UpdateTerms do
  it "creates billing terms and records an audit log" do
    party = create(:booking_billing_party)
    actor = create(:user, account: party.hotel.account)

    expect {
      @result = described_class.call(
        party: party,
        actor: actor,
        attributes: {
          settlement_type: "cash_bank",
          purchase_order_reference: "PO-123",
          authorization_reference: "AUTH-9",
          ignored: "value"
        }
      )
    }.to change(BookingBillingTerms, :count).by(1)
      .and change { BookingAuditLog.where(auditable: party.booking, action_type: "billing_terms_updated").count }.by(1)

    result = @result
    terms = result.terms
    audit_log = BookingAuditLog.where(auditable: party.booking, action_type: "billing_terms_updated").order(:id).last
    expect(result).to be_success
    expect(terms).to have_attributes(
      booking_billing_party: party,
      settlement_type: "cash_bank",
      purchase_order_reference: "PO-123",
      authorization_reference: "AUTH-9",
      created_by: actor,
      updated_by: actor
    )
    expect(audit_log).to have_attributes(hotel: party.hotel, user: actor, category: "financial", source: "booking_control_panel")
    expect(audit_log.new_value).to include(
      "settlement_type" => "cash_bank",
      "purchase_order_reference" => "PO-123",
      "authorization_reference" => "AUTH-9"
    )
  end

  it "updates existing terms using only supported attributes" do
    party = create(:booking_billing_party)
    terms = create(:booking_billing_terms, booking_billing_party: party, settlement_type: "cash_bank", purchase_order_reference: "OLD")
    actor = create(:user, account: party.hotel.account)

    result = described_class.call(
      party: party,
      actor: actor,
      attributes: { settlement_type: "cash_bank", purchase_order_reference: "NEW", billing_reference: "IGNORED" }
    )

    expect(result).to be_success
    expect(result.terms).to eq(terms)
    expect(terms.reload).to have_attributes(purchase_order_reference: "NEW", updated_by: actor)
    expect(terms).not_to respond_to(:billing_reference)
  end

  it "returns validation errors without creating an audit log" do
    account = create(:hotel_corporate_account, direct_bill_enabled: false)
    party = create(:booking_billing_party, hotel: account.hotel, booking: create(:booking, hotel: account.hotel), hotel_corporate_account: account)
    actor = create(:user, account: party.hotel.account)

    expect {
      @result = described_class.call(party: party, actor: actor, attributes: { settlement_type: "city_ledger" })
    }.not_to change(BookingAuditLog, :count)

    expect(@result).not_to be_success
    expect(@result.error).to include("Purchase order reference can't be blank")
    expect(@result.error).to include("Settlement type requires an active Direct Bill")
  end
end
