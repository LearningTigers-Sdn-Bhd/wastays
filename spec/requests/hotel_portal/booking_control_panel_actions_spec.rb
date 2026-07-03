# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::BookingControlPanelActions", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:manage_bookings) { Permission.find_or_create_by!(slug: "manage_bookings") { |permission| permission.name = "Manage Bookings" } }
  let(:manage_folio_windows) { Permission.find_or_create_by!(slug: "manage_folio_windows") { |permission| permission.name = "Manage Folio Windows" } }
  let(:booking) { create(:booking, hotel: hotel) }

  before do
    role.permissions << manage_bookings
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "changes the primary guest only inside the selected booking" do
    original = create(:booking_guest, booking: booking, is_primary: true)
    replacement = create(:booking_guest, booking: booking, is_primary: false)
    sibling = create(:booking)
    sibling_primary = create(:booking_guest, booking: sibling, is_primary: true)

    patch set_primary_guest_hotel_booking_control_panel_path(hotel, booking), params: { booking_guest_id: replacement.id }

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "guest_details", booking_guest_id: replacement.id))
    expect(replacement.reload).to be_primary
    expect(original.reload).not_to be_primary
    expect(sibling_primary.reload).to be_primary
  end

  it "applies a group billing arrangement only to explicitly selected children" do
    allow(BookingRedesign).to receive(:enabled?).and_return(true)
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)
    sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
    arrangement = create(:group_billing_arrangement, group_booking: group, hotel: hotel)

    post apply_billing_hotel_booking_control_panel_path(hotel, booking), params: {
      group_billing_arrangement_id: arrangement.id,
      booking_ids: [ booking.id ],
      charge_categories: [ "accommodation" ],
      billing_scope: "booking",
      local_exception: true
    }

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences", billing_scope: "booking"))
    expect(booking.booking_billing_assignments.sole).to have_attributes(charge_category: "accommodation", local_exception: true)
    expect(sibling.booking_billing_assignments).to be_empty
  end

  it "rejects group actions when the backend gate is disabled" do
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)
    arrangement = create(:group_billing_arrangement, group_booking: group, hotel: hotel)

    post apply_billing_hotel_booking_control_panel_path(hotel, booking), params: {
      group_billing_arrangement_id: arrangement.id,
      booking_ids: [ booking.id ],
      charge_categories: [ "accommodation" ]
    }

    expect(response).to have_http_status(:not_found)
  end

  it "renders the create folio window offcanvas from billing parties" do
    role.permissions << manage_folio_windows
    create(:booking_guest, booking: booking, guest: create(:guest, name: "Aina Rahman"), is_primary: true)

    get new_folio_window_hotel_booking_control_panel_path(hotel, booking)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Add Folio Window")
    expect(response.body).to include("Sharer / Billing party")
    expect(response.body).to include("Aina Rahman")
    expect(response.body).not_to include("Set this folio as primary")
    expect(response.body).not_to include("booking_folio[payer_type]")
  end

  it "creates a folio window from a billing party and returns to Folio Operations" do
    role.permissions << manage_folio_windows
    party = create(:booking_guest, booking: booking).booking_billing_party
    routing_rule_count = FolioRoutingRule.count

    expect do
      post create_folio_window_hotel_booking_control_panel_path(hotel, booking), params: {
        folio_window: {
          booking_billing_party_id: party.id,
          name: "Incidentals Folio",
          currency: "MYR"
        }
      }
    end.to change(BookingFolio, :count).by(1)

    folio = BookingFolio.order(:created_at).last
    expect(folio).to have_attributes(booking_billing_party: party, name: "Incidentals Folio", is_primary: false)
    expect(FolioRoutingRule.count).to eq(routing_rule_count)
    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "folio_operations", folio_id: folio.id))
  end

  it "redirects failed folio window creation back to Folio Operations" do
    role.permissions << manage_folio_windows
    foreign_party = create(:booking_guest).booking_billing_party

    post create_folio_window_hotel_booking_control_panel_path(hotel, booking), params: {
      folio_window: { booking_billing_party_id: foreign_party.id }
    }

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "folio_operations"))
    expect(flash[:alert]).to eq("Select an active billing party for this booking.")
  end

  it "adds and edits a company billing party through inline Billing Preferences actions" do
    account = create(:hotel_corporate_account, hotel: hotel, direct_bill_enabled: true)

    post add_billing_party_hotel_booking_control_panel_path(hotel, booking), params: {
      billing_party: { hotel_corporate_account_id: account.id, settlement_type: "city_ledger", purchase_order_reference: "PO-100" }
    }

    party = booking.booking_billing_parties.companies.sole
    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences", billing_party_id: party.id))
    expect(party.billing_terms).to have_attributes(settlement_type: "city_ledger", purchase_order_reference: "PO-100")

    patch update_billing_terms_hotel_booking_control_panel_path(hotel, booking), params: {
      billing_party_id: party.id, billing_terms: { settlement_type: "cash_bank", billing_reference: "BILL-9" }
    }

    expect(party.billing_terms.reload).to have_attributes(settlement_type: "cash_bank", billing_reference: "BILL-9")
  end

  it "creates a group billing arrangement inline without creating routing rules" do
    allow(BookingRedesign).to receive(:enabled?).and_return(true)
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)
    account = create(:hotel_corporate_account, hotel: hotel, direct_bill_enabled: true)

    expect do
      post create_group_billing_arrangement_hotel_booking_control_panel_path(hotel, booking), params: {
        group_billing_arrangement: { name: "Acme rooms", payer_type: "company", hotel_corporate_account_id: account.id,
          settlement_type: "city_ledger", status: "active", charge_categories: [ "accommodation" ] }
      }
    end.not_to change(FolioRoutingRule, :count)

    expect(group.group_billing_arrangements.sole).to have_attributes(name: "Acme rooms", coverage: { "accommodation" => true })
  end

  it "collects and releases booking-level security deposits" do
    create(:booking_folio, booking: booking, hotel: hotel, is_primary: true)

    post collect_security_deposit_hotel_booking_control_panel_path(hotel, booking), params: {
      amount: "200.00",
      payment_method: "cash",
      external_reference: "SEC-001"
    }

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "security_deposits"))
    expect(booking.deposits.sole).to have_attributes(status: "held", amount: 200.to_d, external_reference: "SEC-001")

    post release_security_deposits_hotel_booking_control_panel_path(hotel, booking), params: {
      method: "cash",
      reference: "REL-001"
    }

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "security_deposits"))
    expect(booking.deposits.sole.reload).to have_attributes(status: "released")
  end

  it "updates booking requests and returns to the control panel Requests tab" do
    housekeeping = create(:housekeeping_request, booking: booking, status: "pending")
    complaint = create(:complaint_request, booking: booking, status: "pending")

    post complete_housekeeping_request_hotel_booking_control_panel_path(hotel, booking), params: { housekeeping_request_id: housekeeping.id }
    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "housekeeping_requests"))
    expect(housekeeping.reload.status).to eq("completed")

    post resolve_complaint_request_hotel_booking_control_panel_path(hotel, booking), params: { complaint_request_id: complaint.id }
    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "housekeeping_requests"))
    expect(complaint.reload.status).to eq("resolved")
  end

  it "does not update a request from another booking in the same hotel" do
    other_booking = create(:booking, hotel: hotel)
    housekeeping = create(:housekeeping_request, booking: other_booking, status: "pending")

    post complete_housekeeping_request_hotel_booking_control_panel_path(hotel, booking), params: { housekeeping_request_id: housekeeping.id }

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "housekeeping_requests"))
    expect(housekeeping.reload.status).to eq("pending")
  end
end
