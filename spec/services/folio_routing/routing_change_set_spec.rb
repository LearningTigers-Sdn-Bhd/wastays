# frozen_string_literal: true

require "rails_helper"

RSpec.describe FolioRouting::RoutingChangeSet do
  let(:booking) { create(:booking) }
  let(:booking_guest) { create(:booking_guest, booking:) }
  let(:guest_party) { booking_guest.booking_billing_party }
  let!(:primary_folio) { create(:booking_folio, booking:, hotel: booking.hotel, is_primary: true, booking_billing_party: guest_party) }
  let(:company_party) { create(:booking_billing_party, :company, booking:, hotel: booking.hotel) }
  let(:company_folio) do
    create(:booking_folio, :secondary, booking:, hotel: booking.hotel, booking_billing_party: company_party,
      payer_type: "company", hotel_corporate_account: company_party.hotel_corporate_account)
  end
  let(:parent_code) { booking.hotel.transaction_codes.find_by!(system_key: "room_revenue") }

  it "answers the parent route change implied by the submitted routes" do
    set = described_class.build(booking:, routes: {
      parent_code.id.to_s => { "billing_party_id" => company_party.id.to_s, "target_folio_id" => company_folio.id.to_s }
    })

    expect(set).to be_valid
    expect(set.error).to be_nil
    expect(set.changes.sole).to include(folio: company_folio)
    expect(set.changes.sole[:row].code).to eq(parent_code)
    expect(set.child_changes).to be_empty
    expect(set.tax_changes).to be_empty
    expect(set.all_changes.size).to eq(1)
    expect(set).to be_any
  end

  it "reports no changes when the route already points at its target" do
    set = described_class.build(booking:, routes: {
      parent_code.id.to_s => { "billing_party_id" => guest_party.id.to_s, "target_folio_id" => primary_folio.id.to_s }
    })

    expect(set).to be_valid
    expect(set).not_to be_any
  end

  it "builds the routing matrix once for all three stages" do
    expect(FolioRouting::RoutingMatrix).to receive(:new).once.and_call_original

    described_class.build(booking:, routes: {
      parent_code.id.to_s => {
        "billing_party_id" => company_party.id.to_s,
        "target_folio_id" => company_folio.id.to_s,
        "children" => { "primary:sst_tax" => { "billing_party_choice" => "guest_primary_folio" } },
        "taxes" => { "primary:tourism_tax" => "1" }
      }
    })
  end

  it "stops at the first failing stage so the most specific message survives" do
    # An unknown code is rejected by the parent stage as "code or folio", and
    # would be rejected again by the child and tax stages with a vaguer message.
    set = described_class.build(booking:, routes: {
      "0" => { "billing_party_id" => company_party.id.to_s, "target_folio_id" => company_folio.id.to_s,
               "children" => { "primary:sst_tax" => { "billing_party_choice" => "inherit" } } }
    })

    expect(set).not_to be_valid
    expect(set.error).to eq("A selected transaction code or folio is unavailable.")
    expect(set.child_changes).to be_empty
    expect(set.tax_changes).to be_empty
  end

  it "reports the last failure within a stage" do
    company_folio.update_columns(status: "closed")

    set = described_class.build(booking:, routes: {
      "0" => { "billing_party_id" => company_party.id.to_s, "target_folio_id" => company_folio.id.to_s },
      parent_code.id.to_s => { "billing_party_id" => company_party.id.to_s, "target_folio_id" => company_folio.id.to_s }
    })

    expect(set.error).to eq("Billing routes can only target an open folio.")
  end
end
