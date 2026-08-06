# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::WorkspaceActions", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:manage_bookings) { Permission.find_or_create_by!(slug: "manage_bookings") { |permission| permission.name = "Manage Bookings" } }
  let(:manage_folio_movements) { Permission.find_or_create_by!(slug: "manage_folio_movements") { |permission| permission.name = "Manage Folio Movements" } }
  let(:view_bookings) { Permission.find_or_create_by!(slug: "view_bookings") { |permission| permission.name = "View Bookings" } }
  let(:booking) { create(:booking, hotel: hotel) }

  before do
    role.permissions << manage_bookings
    role.permissions << view_bookings
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "renders the staged billing routes Sheet for authorized staff" do
    role.permissions << manage_folio_movements
    party = create(:booking_billing_party, :company, booking:, hotel: hotel)
    create(:booking_folio, :secondary, booking:, hotel:, booking_billing_party: party,
      payer_type: "company", hotel_corporate_account: party.hotel_corporate_account, label: "Company Folio")
    create(:transaction_code, hotel:, kind: "charge", code: "ROOMX", name: "Room charge")

    get hotel_folio_action_billing_routes_path(hotel, booking)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Change billing routes", "Billing party", "Target folio", "Apply changes", "Room charge")
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
      payer_type: "company", hotel_corporate_account: party.hotel_corporate_account, label: "Company Folio")
    routes = {
      parent_code.id.to_s => {
        "billing_party_id" => party.id.to_s,
        "target_folio_id" => folio.id.to_s,
        "taxes" => { "primary:sst_tax" => "1" }
      }
    }

    post hotel_folio_action_billing_routes_path(hotel, booking), params: {
      workflow_step: "preview",
      idempotency_key: "tax-only-preview",
      routes: routes
    }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Tax inclusion changes", "SPA", "SST 8%", "Include")

    expect do
      post hotel_folio_action_billing_routes_path(hotel, booking), params: {
        workflow_step: "apply",
        idempotency_key: "tax-only-apply",
        reason: "Route SST to booking billing rules",
        routes: routes
      }
    end.to change(BookingTaxInclusionOverride, :count).by(1)

    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences"))
    expect(booking.booking_tax_inclusion_overrides.sole).to have_attributes(
      transaction_code: parent_code,
      primary_tax_key: "sst_tax",
      action: "include",
      reason: "Route SST to booking billing rules"
    )
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
      payer_type: "company", hotel_corporate_account: party.hotel_corporate_account, label: "Sibling Company Folio")
    code = create(:transaction_code, hotel: hotel, code: "ROOMBULK", category: "accommodation")

    get hotel_folio_action_billing_routes_path(hotel, booking, route_booking_id: sibling.id)
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Change billing routes", booking.formatted_reservation_number, sibling.formatted_reservation_number, "Sibling Company Folio")

    post hotel_folio_action_billing_routes_path(hotel, booking), params: {
      workflow_step: "apply",
      route_booking_id: sibling.id,
      idempotency_key: "selected-child-request",
      confirmation: "future_only",
      reason: "Approved child payer",
      routes: { code.id.to_s => { billing_party_id: party.id.to_s, target_folio_id: target.id.to_s } }
    }

    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, sibling, tab: "billing_preferences"))
    expect(sibling.folio_routing_rules.active.find_by(transaction_code: code)).to be_present
    expect(booking.folio_routing_rules.active.where(transaction_code: code)).to be_empty
  end

  it "requires folio movement permission for group-context route preview" do
    allow(BookingRedesign).to receive(:enabled?).and_return(true)
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)

    post hotel_folio_action_billing_routes_path(hotel, booking), params: { workflow_step: "preview" }

    expect(response).to have_http_status(:found)
    expect(response).to redirect_to(root_path)
  end

  it "offers a guest-primary folio option for tax attachment routing" do
    role.permissions << manage_folio_movements
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    guest = create(:booking_guest, booking: booking, is_primary: true)
    create(:booking_folio, booking: booking, hotel: hotel, is_primary: true,
      booking_billing_party: guest.booking_billing_party)

    get hotel_folio_action_billing_routes_path(hotel, booking)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Keep in Guest Primary Folio")
  end

  it "adds and edits a company billing party through inline Billing Preferences actions" do
    account = create(:hotel_corporate_account, :direct_bill, hotel: hotel)

    post add_billing_party_hotel_booking_workspace_path(hotel, booking), params: {
      billing_party: { hotel_corporate_account_id: account.id, settlement_type: "city_ledger", purchase_order_reference: "PO-100" }
    }

    party = booking.booking_billing_parties.companies.sole
    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences", billing_editor: "party", billing_party_id: party.id))
    expect(party.billing_terms).to have_attributes(settlement_type: "city_ledger", purchase_order_reference: "PO-100")

    patch update_billing_terms_hotel_booking_workspace_path(hotel, booking), params: {
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
      post add_billing_party_hotel_booking_workspace_path(hotel, booking), params: {
        scope: "booking",
        billing_party: { hotel_corporate_account_id: account.id, settlement_type: "city_ledger", purchase_order_reference: "CHILD-PO" }
      }
    end.to change { booking.booking_billing_parties.companies.count }.by(1)
      .and change { BookingFolio.count }.by(1)

    party = booking.booking_billing_parties.companies.sole
    patch update_billing_terms_hotel_booking_workspace_path(hotel, booking), params: {
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
      post add_billing_party_hotel_booking_workspace_path(hotel, booking), params: {
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
      post add_billing_party_hotel_booking_workspace_path(hotel, booking), params: {
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

    patch archive_billing_party_hotel_booking_workspace_path(hotel, booking), params: { billing_party_id: party.id }

    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences"))
    expect(party.reload.archived_at).to be_present
  end

  it "does not remove a company billing party that owns a folio" do
    party = create(:booking_billing_party, :company, booking: booking, hotel: hotel)
    create(:booking_folio, :secondary, booking: booking, hotel: hotel, booking_billing_party: party,
      hotel_corporate_account: party.hotel_corporate_account)

    patch archive_billing_party_hotel_booking_workspace_path(hotel, booking), params: { billing_party_id: party.id }

    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences"))
    expect(flash[:alert]).to eq("Billing parties with folios cannot be archived.")
    expect(party.reload.archived_at).to be_nil
  end

  it "collects and releases booking-level security deposits" do
    create(:booking_folio, booking: booking, hotel: hotel, is_primary: true)

    post collect_security_deposit_hotel_booking_workspace_path(hotel, booking), params: {
      amount: "200.00",
      payment_method: "cash",
      external_reference: "SEC-001"
    }

    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "security_deposits"))
    expect(booking.deposits.sole).to have_attributes(status: "held", amount: 200.to_d, external_reference: "SEC-001")

    post release_security_deposits_hotel_booking_workspace_path(hotel, booking), params: {
      method: "cash",
      reference: "REL-001"
    }

    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "security_deposits"))
    expect(booking.deposits.sole.reload).to have_attributes(status: "released")
  end

  it "records and immediately applies a booking prepayment" do
    folio = create(:booking_folio, booking: booking, hotel: hotel, is_primary: true, currency: booking.currency)

    post record_deposit_hotel_booking_workspace_path(hotel, booking), params: {
      owner: "booking:#{booking.id}", kind: "prepayment", amount: "90.00",
      payment_method: "cash", external_reference: "PRE-001", operation_key: "record-pre-001"
    }

    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "security_deposits"))
    deposit = booking.deposits.sole
    expect(deposit).to have_attributes(kind: "prepayment", status: "settled", amount: 90.to_d)
    expect(deposit.deposit_movements.movement_type_apply.sole.booking_folio).to eq(folio)
  end

  it "uses reason-coded charge application for security deposits in the workspace" do
    permission = Permission.find_or_create_by!(slug: "post_folio_charges") { |record| record.name = "Post folio charges" }
    role.permissions << permission
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
    folio = create(:booking_folio, booking: booking, hotel: hotel, is_primary: true, currency: booking.currency)
    deposit = create(:deposit, booking: booking, hotel: hotel, amount: 100, currency: booking.currency)
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    code = hotel.transaction_codes.find_by!(system_key: "damage_revenue")

    expect {
      post allocate_deposit_hotel_booking_workspace_path(hotel, booking), params: {
        deposit_id: deposit.id,
        booking_folio_id: folio.id,
        transaction_code_id: code.id,
        amount: "30.00",
        operation_key: "workspace-damage-1"
      }
    }.to change { deposit.deposit_movements.movement_type_apply.count }.by(1)

    expect(folio.folio_transactions.charge.last).to have_attributes(transaction_code: code, amount: 30.to_d)
    expect(deposit.reload.available_amount).to eq(70.to_d)
  end

  it "reverses an application from the unified deposit workflow" do
    correction = Permission.find_or_create_by!(slug: "post_folio_corrections") do |permission|
      permission.name = "Post Folio Corrections"
    end
    role.permissions << correction
    folio = create(:booking_folio, booking: booking, hotel: hotel, is_primary: true, currency: booking.currency)
    deposit = create(:deposit, :prepayment, booking: booking, hotel: hotel, amount: 100, currency: booking.currency)
    application = Deposits::Apply.call(deposit: deposit, booking_folio: folio, amount: 60).movement

    post reverse_deposit_application_hotel_booking_workspace_path(hotel, booking), params: {
      deposit_movement_id: application.id, reason: "Applied to the wrong folio", operation_key: "reverse-pre-001"
    }

    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: folio.id))
    expect(application.reload.reversal).to have_attributes(movement_type: "reverse", amount: 60.to_d)
    expect(deposit.reload.available_amount).to eq(100.to_d)
  end

  it "updates booking requests and returns to the control panel Requests tab" do
    housekeeping = create(:housekeeping_request, booking: booking, status: "pending")
    complaint = create(:complaint_request, booking: booking, status: "pending")

    post complete_housekeeping_request_hotel_booking_workspace_path(hotel, booking), params: { housekeeping_request_id: housekeeping.id }
    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "housekeeping_requests"))
    expect(housekeeping.reload.status).to eq("completed")

    post resolve_complaint_request_hotel_booking_workspace_path(hotel, booking), params: { complaint_request_id: complaint.id }
    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "housekeeping_requests"))
    expect(complaint.reload.status).to eq("resolved")
  end

  it "does not update a request from another booking in the same hotel" do
    other_booking = create(:booking, hotel: hotel)
    housekeeping = create(:housekeeping_request, booking: other_booking, status: "pending")

    post complete_housekeeping_request_hotel_booking_workspace_path(hotel, booking), params: { housekeeping_request_id: housekeeping.id }

    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "housekeeping_requests"))
    expect(housekeeping.reload.status).to eq("pending")
  end

  describe "group billing routes" do
    before { allow(BookingRedesign).to receive(:enabled?).and_return(true) }

    it "renders the group billing routes Sheet listing every sibling" do
      role.permissions << manage_folio_movements
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1, reservation_number: 201)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, reservation_number: 202)
      create(:booking_folio, booking: booking, hotel: hotel, is_primary: true)
      create(:booking_folio, booking: sibling, hotel: hotel, is_primary: true)

      get hotel_folio_action_group_billing_routes_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Change group billing routes", booking.formatted_reservation_number, sibling.formatted_reservation_number)
    end

    it "requires folio movement permission" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)

      get hotel_folio_action_group_billing_routes_path(hotel, booking)

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

      get hotel_folio_action_group_billing_routes_path(hotel, booking)

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

      post hotel_folio_action_group_billing_routes_path(hotel, booking), params: {
        workflow_step: "preview",
        idempotency_key: "group-preview", group_routes: group_routes
      }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Existing charge impact")

      post hotel_folio_action_group_billing_routes_path(hotel, booking), params: {
        workflow_step: "apply",
        idempotency_key: "group-apply", confirmation: "future_only", reason: "Split group billing", group_routes: group_routes
      }

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences", scope: "group"))
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

      post hotel_folio_action_group_billing_routes_path(hotel, booking), params: {
        workflow_step: "apply",
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
