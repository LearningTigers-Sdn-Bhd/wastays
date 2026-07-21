# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::BookingControlPanelActions", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:manage_bookings) { Permission.find_or_create_by!(slug: "manage_bookings") { |permission| permission.name = "Manage Bookings" } }
  let(:manage_folio_windows) { Permission.find_or_create_by!(slug: "manage_folio_windows") { |permission| permission.name = "Manage Folio Windows" } }
  let(:manage_folio_movements) { Permission.find_or_create_by!(slug: "manage_folio_movements") { |permission| permission.name = "Manage Folio Movements" } }
  let(:booking) { create(:booking, hotel: hotel) }

  before do
    role.permissions << manage_bookings
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "renders the staged billing routes offcanvas for authorized staff" do
    role.permissions << manage_folio_movements
    party = create(:booking_billing_party, :company, booking:, hotel: hotel)
    create(:booking_folio, :secondary, booking:, hotel:, booking_billing_party: party,
      payer_type: "company", hotel_corporate_account: party.hotel_corporate_account, name: "Company Folio")
    create(:transaction_code, hotel:, kind: "charge", code: "ROOMX", name: "Room charge")

    get billing_routes_hotel_booking_control_panel_path(hotel, booking)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Change Billing Routes", "Billing party", "Target folio", "Apply changes", "Room charge")
    headers = Nokogiri::HTML(response.body).css("table thead th").map { |node| node.text.squish }
    expect(headers).not_to include("Status", "Action")
  end

  it "reviews and applies tax-only billing route inclusion changes" do
    role.permissions << manage_folio_movements
    hotel.update!(sst_enabled: true)
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    parent_code = create(:transaction_code, hotel:, kind: "charge", code: "SPA", name: "Spa charge")
    party = create(:booking_billing_party, :company, booking:, hotel:)
    folio = create(:booking_folio, :secondary, booking:, hotel:, booking_billing_party: party,
      payer_type: "company", hotel_corporate_account: party.hotel_corporate_account, name: "Company Folio")
    routes = {
      parent_code.id.to_s => {
        "billing_party_id" => party.id.to_s,
        "target_folio_id" => folio.id.to_s,
        "taxes" => { "primary:sst_tax" => "1" }
      }
    }

    post preview_billing_routes_hotel_booking_control_panel_path(hotel, booking), params: {
      idempotency_key: "tax-only-preview",
      routes: routes
    }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Tax inclusion changes", "SPA", "SST 8%", "Include")

    expect do
      post apply_billing_routes_hotel_booking_control_panel_path(hotel, booking), params: {
        idempotency_key: "tax-only-apply",
        reason: "Route SST to booking billing rules",
        routes: routes
      }
    end.to change(BookingTaxInclusionOverride, :count).by(1)

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences"))
    expect(booking.booking_tax_inclusion_overrides.sole).to have_attributes(
      transaction_code: parent_code,
      primary_tax_key: "sst_tax",
      action: "include",
      reason: "Route SST to booking billing rules"
    )
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

  it "renders and applies billing routes for the selected group child booking" do
    allow(BookingRedesign).to receive(:enabled?).and_return(true)
    role.permissions << manage_folio_movements
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1, reservation_number: 101)
    sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, reservation_number: 102)
    [ booking, sibling ].each do |child|
      create(:booking_room, booking: child)
      guest = create(:booking_guest, booking: child, is_primary: true)
      create(:booking_folio, booking: child, hotel: hotel, is_primary: true,
        booking_billing_party: guest.booking_billing_party)
    end
    party = create(:booking_billing_party, :company, booking: sibling, hotel: hotel)
    target = create(:booking_folio, :secondary, booking: sibling, hotel: hotel, booking_billing_party: party,
      payer_type: "company", hotel_corporate_account: party.hotel_corporate_account, name: "Sibling Company Folio")
    code = create(:transaction_code, hotel: hotel, code: "ROOMBULK", category: "accommodation")

    get billing_routes_hotel_booking_control_panel_path(hotel, booking, route_booking_id: sibling.id)
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Change Billing Routes", booking.formatted_reservation_number, sibling.formatted_reservation_number, "Sibling Company Folio")

    post apply_billing_routes_hotel_booking_control_panel_path(hotel, booking), params: {
      route_booking_id: sibling.id,
      idempotency_key: "selected-child-request",
      confirmation: "future_only",
      reason: "Approved child payer",
      routes: { code.id.to_s => { billing_party_id: party.id.to_s, target_folio_id: target.id.to_s } }
    }

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, sibling, tab: "billing_preferences"))
    expect(sibling.folio_routing_rules.active.find_by(transaction_code: code)).to be_present
    expect(booking.folio_routing_rules.active.where(transaction_code: code)).to be_empty
  end

  it "requires folio movement permission for group-context route preview" do
    allow(BookingRedesign).to receive(:enabled?).and_return(true)
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)

    post preview_billing_routes_hotel_booking_control_panel_path(hotel, booking), params: {}

    expect(response).to have_http_status(:found)
    expect(response).to redirect_to(root_path)
  end

  it "offers a guest-primary folio option for tax attachment routing" do
    role.permissions << manage_folio_movements
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    guest = create(:booking_guest, booking: booking, is_primary: true)
    create(:booking_folio, booking: booking, hotel: hotel, is_primary: true,
      booking_billing_party: guest.booking_billing_party)

    get billing_routes_hotel_booking_control_panel_path(hotel, booking)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Keep in Guest Primary Folio")
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

  it "renders a booking selector when adding a folio in group context" do
    role.permissions << manage_folio_windows
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1, reservation_number: 41)
    sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, reservation_number: 42)
    create(:booking_room, booking: booking, room_number: "105")
    create(:booking_room, booking: sibling, room_number: "106")
    create(:booking_guest, booking: booking, guest: create(:guest, name: "Guest One"), is_primary: true)
    create(:booking_guest, booking: sibling, guest: create(:guest, name: "Guest Two"), is_primary: true)

    get new_folio_window_hotel_booking_control_panel_path(hotel, booking, scope: "group")

    document = Nokogiri::HTML(response.body)
    booking_select = document.at_css('select[name="folio_window[booking_id]"]')
    expect(booking_select).to be_present
    expect(booking_select.css("option").map(&:text)).to include(
      "Room 105 · Booking No. #{booking.formatted_reservation_number}",
      "Room 106 · Booking No. #{sibling.formatted_reservation_number}"
    )
    expect(response.body).to include("Guest One", "Guest Two")
  end

  it "creates a group-context folio on the selected child booking" do
    role.permissions << manage_folio_windows
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)
    sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
    sibling_party = create(:booking_guest, booking: sibling).booking_billing_party
    original_booking_folio_count = booking.booking_folios.count

    expect do
      post create_folio_window_hotel_booking_control_panel_path(hotel, booking), params: {
        folio_window: {
          booking_id: sibling.id,
          booking_billing_party_id: sibling_party.id,
          name: "Room 106 Incidentals",
          currency: "MYR"
        }
      }
    end.to change { sibling.booking_folios.count }.by(1)

    folio = sibling.booking_folios.order(:created_at).last
    expect(booking.booking_folios.count).to eq(original_booking_folio_count)
    expect(folio).to have_attributes(name: "Room 106 Incidentals", booking_billing_party: sibling_party)
    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, sibling, tab: "folio_operations", folio_id: folio.id))
  end

  it "rejects a folio target outside the current group" do
    role.permissions << manage_folio_windows
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)
    outsider = create(:booking, hotel: hotel)
    outsider_party = create(:booking_guest, booking: outsider).booking_billing_party

    post create_folio_window_hotel_booking_control_panel_path(hotel, booking), params: {
      folio_window: { booking_id: outsider.id, booking_billing_party_id: outsider_party.id }
    }

    expect(response).to have_http_status(:not_found)
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

  it "edits a folio window through the control panel" do
    role.permissions << manage_folio_windows
    folio = create(:booking_folio, booking: booking, hotel: hotel, name: "Original Folio")

    get edit_folio_window_hotel_booking_control_panel_path(hotel, booking, folio)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Edit Folio Window", "Original Folio")

    patch update_folio_window_hotel_booking_control_panel_path(hotel, booking, folio), params: {
      booking_folio: { name: "Updated Folio", folio_type: folio.folio_type, payer_type: folio.payer_type }
    }

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "folio_operations", folio_id: folio.id))
    expect(folio.reload.name).to eq("Updated Folio")
  end

  it "closes and reopens a settled folio through the control panel" do
    role.permissions << manage_folio_windows
    folio = create(:booking_folio, booking: booking, hotel: hotel)

    post close_folio_window_hotel_booking_control_panel_path(hotel, booking, folio), params: {
      booking_folio: { reason: "Window no longer needed" }
    }

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "folio_operations", folio_id: folio.id))
    expect(folio.reload).to be_closed

    post reopen_folio_window_hotel_booking_control_panel_path(hotel, booking, folio), params: {
      booking_folio: { reason: "Correction required" }
    }

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "folio_operations", folio_id: folio.id))
    expect(folio.reload).to be_open
  end

  it "edits, closes, and reopens a folio window on a group child booking" do
    role.permissions << manage_folio_windows
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)
    sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
    folio = create(:booking_folio, booking: sibling, hotel: hotel, name: "Original Folio")

    get edit_folio_window_hotel_booking_control_panel_path(hotel, sibling, folio)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Edit Folio Window", "Original Folio")

    patch update_folio_window_hotel_booking_control_panel_path(hotel, sibling, folio), params: {
      booking_folio: { name: "Updated Folio", folio_type: folio.folio_type, payer_type: folio.payer_type }
    }

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, sibling, tab: "folio_operations", folio_id: folio.id))
    expect(folio.reload.name).to eq("Updated Folio")

    post close_folio_window_hotel_booking_control_panel_path(hotel, sibling, folio), params: {
      booking_folio: { reason: "Window no longer needed" }
    }

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, sibling, tab: "folio_operations", folio_id: folio.id))
    expect(folio.reload).to be_closed

    post reopen_folio_window_hotel_booking_control_panel_path(hotel, sibling, folio), params: {
      booking_folio: { reason: "Correction required" }
    }

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, sibling, tab: "folio_operations", folio_id: folio.id))
    expect(folio.reload).to be_open
  end

  it "rejects folio window edit/close/reopen through a different booking in the same group" do
    role.permissions << manage_folio_windows
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)
    sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
    folio = create(:booking_folio, booking: sibling, hotel: hotel)

    get edit_folio_window_hotel_booking_control_panel_path(hotel, booking, folio)
    expect(response).to have_http_status(:not_found)

    patch update_folio_window_hotel_booking_control_panel_path(hotel, booking, folio), params: {
      booking_folio: { name: "Hijacked", folio_type: folio.folio_type, payer_type: folio.payer_type }
    }
    expect(response).to have_http_status(:not_found)
    expect(folio.reload.name).not_to eq("Hijacked")

    post close_folio_window_hotel_booking_control_panel_path(hotel, booking, folio), params: {
      booking_folio: { reason: "Window no longer needed" }
    }
    expect(response).to have_http_status(:not_found)
    expect(folio.reload).to be_open

    post reopen_folio_window_hotel_booking_control_panel_path(hotel, booking, folio), params: {
      booking_folio: { reason: "Correction required" }
    }
    expect(response).to have_http_status(:not_found)
  end

  it "adds and edits a company billing party through inline Billing Preferences actions" do
    account = create(:hotel_corporate_account, :direct_bill, hotel: hotel)

    post add_billing_party_hotel_booking_control_panel_path(hotel, booking), params: {
      billing_party: { hotel_corporate_account_id: account.id, settlement_type: "city_ledger", purchase_order_reference: "PO-100" }
    }

    party = booking.booking_billing_parties.companies.sole
    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences", billing_editor: "party", billing_party_id: party.id))
    expect(party.billing_terms).to have_attributes(settlement_type: "city_ledger", purchase_order_reference: "PO-100")

    patch update_billing_terms_hotel_booking_control_panel_path(hotel, booking), params: {
      billing_party_id: party.id, billing_terms: { settlement_type: "cash_bank", authorization_reference: "AUTH-9" }
    }

    expect(party.billing_terms.reload).to have_attributes(settlement_type: "cash_bank", authorization_reference: "AUTH-9")
  end

  it "adds and edits a company billing party only on the selected group child" do
    allow(BookingRedesign).to receive(:enabled?).and_return(true)
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)
    sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
    account = create(:hotel_corporate_account, :direct_bill, hotel: hotel)
    folio_count = BookingFolio.count
    routing_rule_count = FolioRoutingRule.count

    expect do
      post add_billing_party_hotel_booking_control_panel_path(hotel, booking), params: {
        scope: "booking",
        billing_party: { hotel_corporate_account_id: account.id, settlement_type: "city_ledger", purchase_order_reference: "CHILD-PO" }
      }
    end.to change { booking.booking_billing_parties.companies.count }.by(1)
      .and change { BookingFolio.count }.by(1)

    party = booking.booking_billing_parties.companies.sole
    patch update_billing_terms_hotel_booking_control_panel_path(hotel, booking), params: {
      billing_party_id: party.id,
      billing_terms: { settlement_type: "cash_bank", authorization_reference: "CHILD-AUTH" }
    }

    expect(party.billing_terms.reload).to have_attributes(settlement_type: "cash_bank", authorization_reference: "CHILD-AUTH")
    expect(sibling.booking_billing_parties).to be_empty
    expect(FolioRoutingRule.count).to eq(routing_rule_count)
  end

  it "prompts for scope before adding a billing party on a grouped booking" do
    allow(BookingRedesign).to receive(:enabled?).and_return(true)
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)
    create(:booking, hotel: hotel, group_booking: group, group_position: 2)
    account = create(:hotel_corporate_account, :direct_bill, hotel: hotel)

    expect do
      post add_billing_party_hotel_booking_control_panel_path(hotel, booking), params: {
        billing_party: { hotel_corporate_account_id: account.id, settlement_type: "city_ledger", purchase_order_reference: "PO-1" }
      }
    end.not_to change { BookingBillingParty.count }

    expect(response.body).to include("Apply to the whole group?")
  end

  it "applies a billing party to every booking in the group when scope is group" do
    allow(BookingRedesign).to receive(:enabled?).and_return(true)
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)
    sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
    account = create(:hotel_corporate_account, :direct_bill, hotel: hotel)

    expect do
      post add_billing_party_hotel_booking_control_panel_path(hotel, booking), params: {
        scope: "group",
        billing_party: { hotel_corporate_account_id: account.id, settlement_type: "city_ledger", purchase_order_reference: "PO-GROUP" }
      }
    end.to change { BookingBillingParty.count }.by(2)
      .and change { BookingFolio.count }.by(2)

    expect(booking.booking_billing_parties.companies.sole.hotel_corporate_account).to eq(account)
    expect(sibling.booking_billing_parties.companies.sole.hotel_corporate_account).to eq(account)
  end

  it "removes a company billing party without folios" do
    party = create(:booking_billing_party, :company, booking: booking, hotel: hotel)

    patch archive_billing_party_hotel_booking_control_panel_path(hotel, booking), params: { billing_party_id: party.id }

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences"))
    expect(party.reload.archived_at).to be_present
  end

  it "does not remove a company billing party that owns a folio" do
    party = create(:booking_billing_party, :company, booking: booking, hotel: hotel)
    create(:booking_folio, :secondary, booking: booking, hotel: hotel, booking_billing_party: party,
      hotel_corporate_account: party.hotel_corporate_account)

    patch archive_billing_party_hotel_booking_control_panel_path(hotel, booking), params: { billing_party_id: party.id }

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences"))
    expect(flash[:alert]).to eq("Billing parties with folios cannot be archived.")
    expect(party.reload.archived_at).to be_nil
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

  describe "group billing routes" do
    before { allow(BookingRedesign).to receive(:enabled?).and_return(true) }

    it "renders the group billing routes offcanvas listing every sibling" do
      role.permissions << manage_folio_movements
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1, reservation_number: 201)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, reservation_number: 202)
      create(:booking_folio, booking: booking, hotel: hotel, is_primary: true)
      create(:booking_folio, booking: sibling, hotel: hotel, is_primary: true)

      get group_billing_routes_hotel_booking_control_panel_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Change Group Billing Routes", booking.formatted_reservation_number, sibling.formatted_reservation_number)
    end

    it "requires folio movement permission" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)

      get group_billing_routes_hotel_booking_control_panel_path(hotel, booking)

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(root_path)
    end

    it "shows a needs-review reason for a sibling with no billing party" do
      role.permissions << manage_folio_movements
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      guest = create(:booking_guest, booking: booking, is_primary: true)
      create(:booking_folio, booking: booking, hotel: hotel, is_primary: true, booking_billing_party: guest.booking_billing_party)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      create(:booking_folio, booking: sibling, hotel: hotel, is_primary: true)

      get group_billing_routes_hotel_booking_control_panel_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("No billing party assigned")
    end

    it "previews and applies routing changes across every sibling in one batch" do
      role.permissions << manage_folio_movements
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      primary_a = create(:booking_folio, booking: booking, hotel: hotel, is_primary: true)
      create(:booking_folio, booking: sibling, hotel: hotel, is_primary: true)
      party_a = create(:booking_billing_party, :company, booking: booking, hotel: hotel)
      target_a = create(:booking_folio, :secondary, booking: booking, hotel: hotel,
        booking_billing_party: party_a, payer_type: "company", hotel_corporate_account: party_a.hotel_corporate_account)
      party_b = create(:booking_billing_party, :company, booking: sibling, hotel: hotel)
      target_b = create(:booking_folio, :secondary, booking: sibling, hotel: hotel,
        booking_billing_party: party_b, payer_type: "company", hotel_corporate_account: party_b.hotel_corporate_account)
      code = create(:transaction_code, hotel: hotel, kind: "charge")
      create(:folio_transaction, booking_folio: primary_a, transaction_code: code, transaction_type: "charge", amount: 150)
      group_routes = {
        booking.id.to_s => { code.id.to_s => { "billing_party_id" => party_a.id.to_s, "target_folio_id" => target_a.id.to_s } },
        sibling.id.to_s => { code.id.to_s => { "billing_party_id" => party_b.id.to_s, "target_folio_id" => target_b.id.to_s } }
      }

      post preview_group_billing_routes_hotel_booking_control_panel_path(hotel, booking), params: {
        idempotency_key: "group-preview", group_routes: group_routes
      }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Existing charge impact")

      post apply_group_billing_routes_hotel_booking_control_panel_path(hotel, booking), params: {
        idempotency_key: "group-apply", confirmation: "future_only", reason: "Split group billing", group_routes: group_routes
      }

      expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences", scope: "group"))
      expect(booking.folio_routing_rules.active.find_by(transaction_code: code)&.target_folio).to eq(target_a)
      expect(sibling.folio_routing_rules.active.find_by(transaction_code: code)&.target_folio).to eq(target_b)
    end

    it "rolls back every sibling when one booking's route is invalid" do
      role.permissions << manage_folio_movements
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      create(:booking_folio, booking: booking, hotel: hotel, is_primary: true)
      party_a = create(:booking_billing_party, :company, booking: booking, hotel: hotel)
      target_a = create(:booking_folio, :secondary, booking: booking, hotel: hotel,
        booking_billing_party: party_a, payer_type: "company", hotel_corporate_account: party_a.hotel_corporate_account)
      party_b = create(:booking_billing_party, :company, booking: sibling, hotel: hotel)
      other_party_b = create(:booking_billing_party, :company, booking: sibling, hotel: hotel)
      mismatched_target_b = create(:booking_folio, :secondary, booking: sibling, hotel: hotel,
        booking_billing_party: other_party_b, payer_type: "company", hotel_corporate_account: other_party_b.hotel_corporate_account)
      code = create(:transaction_code, hotel: hotel, kind: "charge")

      post apply_group_billing_routes_hotel_booking_control_panel_path(hotel, booking), params: {
        idempotency_key: "group-rollback", confirmation: "future_only", reason: "Attempt", group_routes: {
          booking.id.to_s => { code.id.to_s => { "billing_party_id" => party_a.id.to_s, "target_folio_id" => target_a.id.to_s } },
          sibling.id.to_s => { code.id.to_s => { "billing_party_id" => party_b.id.to_s, "target_folio_id" => mismatched_target_b.id.to_s } }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(booking.folio_routing_rules.active.where(transaction_code: code)).to be_empty
      expect(sibling.folio_routing_rules.active.where(transaction_code: code)).to be_empty
    end
  end
end
