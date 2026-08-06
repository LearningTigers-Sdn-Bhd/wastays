# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Folios::Actions billing routes", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel) }

  before do
    grant_permission("view_bookings")
    grant_permission("manage_folio_movements")
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  def grant_permission(slug)
    permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    role.permissions << permission unless role.permissions.exists?(permission.id)
  end

  def selective_path(target = booking, **params)
    hotel_folio_action_billing_routes_path(hotel, target, **params)
  end

  def group_path(target = booking, **params)
    hotel_folio_action_group_billing_routes_path(hotel, target, **params)
  end

  def route_target(target_booking = booking)
    party = create(:booking_billing_party, :company, booking: target_booking, hotel: hotel)
    folio = create(:booking_folio, :secondary, booking: target_booking, hotel: hotel,
      booking_billing_party: party, payer_type: "company",
      hotel_corporate_account: party.hotel_corporate_account)
    [ party, folio ]
  end

  describe "selective billing routes" do
    it "renders the staged editor in the requesting Sheet frame" do
      route_target
      create(:transaction_code, hotel: hotel, kind: "charge", code: "ROOMX", name: "Room charge")

      get selective_path, headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#folio_action_sheet dialog#folio-billing-routes-sheet[data-controller='panels-ui--sheet']")).to be_present
      expect(document.at_css("select[name^='routes['][name$='[billing_party_id]']")).to be_present
      expect(document.at_css("select[name^='routes['][name$='[target_folio_id]']")).to be_present
      expect(response.body).to include("Change billing routes", "Billing party", "Target folio", "Room charge")
      expect(response.body).not_to include("offcanvas")
    end

    it "echoes the secondary frame" do
      route_target

      get selective_path, headers: { "Turbo-Frame" => "folio_action_sheet_secondary" }

      expect(Nokogiri::HTML(response.body).at_css("turbo-frame#folio_action_sheet_secondary dialog#folio-billing-routes-sheet")).to be_present
    end

    it "rejects an unknown workflow step inside the Sheet" do
      post selective_path,
        params: { workflow_step: "destroy_everything" },
        headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Select a valid billing-route action.")
      expect(response.body).to include("folio-billing-routes-sheet")
    end

    it "applies a tax-only route change and completes the requesting frame" do
      hotel.update!(sst_enabled: true)
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      code = create(:transaction_code, hotel: hotel, kind: "charge", code: "SPA", name: "Spa charge")
      party, folio = route_target
      destination = hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences")

      post selective_path,
        params: {
          workflow_step: "apply",
          return_to: destination,
          idempotency_key: "tax-only-sheet",
          reason: "Route SST with the spa charge",
          routes: {
            code.id.to_s => {
              billing_party_id: party.id.to_s,
              target_folio_id: folio.id.to_s,
              taxes: { "primary:sst_tax" => "1" }
            }
          }
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet_secondary" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"', 'target="folio_action_sheet_secondary"')
      expect(response.body).to include(%(url="#{destination}"))
      expect(booking.booking_tax_inclusion_overrides.sole).to have_attributes(primary_tax_key: "sst_tax", action: "include")
    end

    it "keeps failed applications in the Sheet" do
      code = create(:transaction_code, hotel: hotel, kind: "charge")
      party, folio = route_target

      post selective_path,
        params: {
          workflow_step: "apply",
          routes: { code.id.to_s => { billing_party_id: party.id.to_s, target_folio_id: folio.id.to_s } }
        },
        headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("missing its idempotency key", "folio-billing-routes-sheet")
      expect(response.body).not_to include('action="complete_sheet"')
    end

    it "scopes a selected child to the path booking's group" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      outsider = create(:booking, hotel: hotel)

      get selective_path(route_booking_id: outsider.id), headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:not_found)
    end

    it "does not find a booking from another hotel" do
      foreign_booking = create(:booking, hotel: other_hotel)

      get selective_path(foreign_booking), headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "group billing routes" do
    let(:group) { create(:group_booking, hotel: hotel) }
    let(:sibling) { create(:booking, hotel: hotel, group_booking: group, group_position: 2) }

    before do
      booking.update!(group_booking: group, group_position: 1)
      [ booking, sibling ].each { |child| create(:booking_folio, booking: child, hotel: hotel, is_primary: true) }
    end

    it "renders a full bottom Sheet for every sibling" do
      get group_path, headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      sheet = document.at_css("turbo-frame#folio_action_sheet dialog#folio-group-billing-routes-sheet")
      expect(sheet).to be_present
      expect(sheet["data-panels-ui-sheet-side"]).to eq("bottom")
      expect(response.body).to include(booking.formatted_reservation_number, sibling.formatted_reservation_number)
    end

    it "applies one atomic batch and completes the Sheet" do
      party_a, target_a = route_target(booking)
      party_b, target_b = route_target(sibling)
      code = create(:transaction_code, hotel: hotel, kind: "charge")

      post group_path,
        params: {
          workflow_step: "apply",
          idempotency_key: "group-sheet-apply",
          confirmation: "future_only",
          reason: "Split group billing",
          group_routes: {
            booking.id.to_s => { code.id.to_s => { billing_party_id: party_a.id.to_s, target_folio_id: target_a.id.to_s } },
            sibling.id.to_s => { code.id.to_s => { billing_party_id: party_b.id.to_s, target_folio_id: target_b.id.to_s } }
          }
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet" }

      expect(response.body).to include('action="complete_sheet"', 'target="folio_action_sheet"')
      expect(booking.folio_routing_rules.active.find_by!(transaction_code: code).target_folio).to eq(target_a)
      expect(sibling.folio_routing_rules.active.find_by!(transaction_code: code).target_folio).to eq(target_b)
    end

    it "rolls back every child when one target is invalid" do
      party_a, target_a = route_target(booking)
      party_b, = route_target(sibling)
      other_party, mismatched_target = route_target(sibling)
      expect(other_party).not_to eq(party_b)
      code = create(:transaction_code, hotel: hotel, kind: "charge")

      post group_path, params: {
        workflow_step: "apply",
        idempotency_key: "group-sheet-rollback",
        confirmation: "future_only",
        reason: "Attempt invalid batch",
        group_routes: {
          booking.id.to_s => { code.id.to_s => { billing_party_id: party_a.id.to_s, target_folio_id: target_a.id.to_s } },
          sibling.id.to_s => { code.id.to_s => { billing_party_id: party_b.id.to_s, target_folio_id: mismatched_target.id.to_s } }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(booking.folio_routing_rules.active.where(transaction_code: code)).to be_empty
      expect(sibling.folio_routing_rules.active.where(transaction_code: code)).to be_empty
    end

    it "requires a group booking" do
      standalone = create(:booking, hotel: hotel)

      get group_path(standalone), headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "permission gates" do
    it "requires manage_folio_movements for both workflows" do
      role.permissions.delete(Permission.find_by!(slug: "manage_folio_movements"))

      [ selective_path, group_path ].each do |path|
        get path, headers: { "Turbo-Frame" => "folio_action_sheet" }
        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to include("not authorized")
      end
    end
  end
end
