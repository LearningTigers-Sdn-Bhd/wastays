# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Folios::Actions windows", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel) }

  before do
    grant_permission("view_bookings")
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  def grant_permission(slug)
    permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.tr("_", " ").titleize }
    role.permissions << permission unless role.permissions.exists?(permission.id)
  end

  def folio_operations_path(target = booking, folio_id: nil)
    query = { tab: "folio_operations" }
    query[:folio_id] = folio_id if folio_id.present?
    hotel_booking_workspace_path(hotel, target, query)
  end

  describe "GET the add-window form" do
    before { grant_permission("manage_folio_windows") }

    it "renders the create Sheet in the primary folio-action frame" do
      create(:booking_guest, booking: booking, guest: create(:guest, name: "Aina Rahman"), is_primary: true)

      get hotel_folio_action_new_window_path(hotel, booking), headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#folio_action_sheet dialog#folio-window-sheet[data-controller='panels-ui--sheet']")).to be_present
      expect(response.body).to include("Add folio window")
      expect(response.body).to include("Sharer / billing party")
      expect(response.body).to include("Aina Rahman")
      expect(response.body).not_to include("Set this folio as primary")
      expect(response.body).not_to include("booking_folio[payer_type]")
      expect(response.body).not_to include("offcanvas")
    end

    it "renders into the secondary frame when launched from a stacked sheet" do
      create(:booking_guest, booking: booking, is_primary: true)

      get hotel_folio_action_new_window_path(hotel, booking), headers: { "Turbo-Frame" => "folio_action_sheet_secondary" }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#folio_action_sheet_secondary dialog#folio-window-sheet")).to be_present
    end

    it "renders a booking selector in group context" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1, reservation_number: 41)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, reservation_number: 42)
      create(:booking_room, booking: booking, room_number: "105")
      create(:booking_room, booking: sibling, room_number: "106")
      create(:booking_guest, booking: booking, guest: create(:guest, name: "Guest One"), is_primary: true)
      create(:booking_guest, booking: sibling, guest: create(:guest, name: "Guest Two"), is_primary: true)

      get hotel_folio_action_new_window_path(hotel, booking), headers: { "Turbo-Frame" => "folio_action_sheet" }

      document = Nokogiri::HTML(response.body)
      booking_select = document.at_css('select[name="folio_window[booking_id]"]')
      expect(booking_select).to be_present
      expect(booking_select.css("option").map(&:text)).to include(
        "Room 105 · Booking No. #{booking.formatted_reservation_number}",
        "Room 106 · Booking No. #{sibling.formatted_reservation_number}"
      )
      expect(response.body).to include("Guest One", "Guest Two")
    end

    it "does not find a booking belonging to another hotel" do
      foreign_booking = create(:booking, hotel: other_hotel)

      get hotel_folio_action_new_window_path(hotel, foreign_booking), headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST the new window" do
    before { grant_permission("manage_folio_windows") }

    it "creates a folio window from a billing party and completes the sheet" do
      party = create(:booking_guest, booking: booking).booking_billing_party
      routing_rule_count = FolioRoutingRule.count

      expect do
        post hotel_folio_action_new_window_path(hotel, booking),
          params: { folio_window: { booking_billing_party_id: party.id, label: "Incidentals Folio", currency: "MYR" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet" }
      end.to change(BookingFolio, :count).by(1)

      folio = BookingFolio.order(:created_at).last
      expect(folio).to have_attributes(booking_billing_party: party, label: "Incidentals Folio", is_primary: false)
      expect(FolioRoutingRule.count).to eq(routing_rule_count)
      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).to include('target="folio_action_sheet"')
      expect(flash[:notice]).to eq("Folio window created.")
    end

    it "creates a group-context folio on the selected child booking" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      sibling_party = create(:booking_guest, booking: sibling).booking_billing_party
      original_count = booking.booking_folios.count

      expect do
        post hotel_folio_action_new_window_path(hotel, booking), params: {
          folio_window: {
            booking_id: sibling.id,
            booking_billing_party_id: sibling_party.id,
            label: "Room 106 Incidentals",
            currency: "MYR"
          }
        }
      end.to change { sibling.booking_folios.count }.by(1)

      folio = sibling.booking_folios.order(:created_at).last
      expect(booking.booking_folios.count).to eq(original_count)
      expect(folio).to have_attributes(label: "Room 106 Incidentals", booking_billing_party: sibling_party)
      expect(response).to redirect_to(folio_operations_path(sibling, folio_id: folio.id))
    end

    it "rejects a folio target outside the current group" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      outsider = create(:booking, hotel: hotel)
      outsider_party = create(:booking_guest, booking: outsider).booking_billing_party

      post hotel_folio_action_new_window_path(hotel, booking),
        params: { folio_window: { booking_id: outsider.id, booking_billing_party_id: outsider_party.id } }

      expect(response).to have_http_status(:not_found)
    end

    it "rejects a folio target on a booking with no group" do
      outsider = create(:booking, hotel: hotel)

      post hotel_folio_action_new_window_path(hotel, booking),
        params: { folio_window: { booking_id: outsider.id } }

      expect(response).to have_http_status(:not_found)
    end

    it "closes the sheet with a flash alert when creation fails" do
      foreign_party = create(:booking_guest).booking_billing_party

      post hotel_folio_action_new_window_path(hotel, booking),
        params: { folio_window: { booking_billing_party_id: foreign_party.id } }

      expect(response).to redirect_to(folio_operations_path)
      expect(flash[:alert]).to eq("Select an active billing party for this booking.")
    end
  end

  describe "the edit window" do
    before { grant_permission("manage_folio_windows") }

    it "renders the edit Sheet and updates the folio" do
      folio = create(:booking_folio, booking: booking, hotel: hotel, label: "Original Folio")

      get hotel_folio_action_edit_window_path(hotel, booking, folio), headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Edit folio window", "Original Folio")
      expect(response.body).to include("Set this folio as primary")

      patch hotel_folio_action_edit_window_path(hotel, booking, folio),
        params: { booking_folio: { label: "Updated Folio", folio_type: folio.folio_type, payer_type: folio.payer_type } }

      expect(response).to redirect_to(folio_operations_path(booking, folio_id: folio.id))
      expect(folio.reload.label).to eq("Updated Folio")
    end

    it "promotes a secondary folio to primary and demotes the previous one" do
      original_primary = create(:booking_folio, booking: booking, hotel: hotel, is_primary: true)
      relationship = create(:hotel_corporate_account, hotel: hotel)
      secondary = create(:booking_folio, :secondary, booking: booking, hotel: hotel,
        payer_type: "company", hotel_corporate_account: relationship)

      expect {
        patch hotel_folio_action_edit_window_path(hotel, booking, secondary), params: {
          booking_folio: {
            label: "Company Folio",
            folio_type: "external",
            payer_type: "company",
            hotel_corporate_account_id: relationship.id,
            is_primary: "1",
            set_folio_as_primary_reason: "Company is now responsible"
          }
        }
      }.to change(FolioOperationLog.where(operation_type: "set_default_folio"), :count).by(1)

      expect(secondary.reload).to be_is_primary
      expect(original_primary.reload).not_to be_is_primary
      expect(booking.reload.booking_folio).to eq(secondary)
    end

    it "completes the frame that launched the sheet" do
      folio = create(:booking_folio, booking: booking, hotel: hotel)

      patch hotel_folio_action_edit_window_path(hotel, booking, folio),
        params: { booking_folio: { label: "Updated", folio_type: folio.folio_type, payer_type: folio.payer_type } },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet_secondary" }

      expect(response.body).to include('target="folio_action_sheet_secondary"')
    end
  end

  describe "closing and reopening" do
    before { grant_permission("manage_folio_windows") }

    it "renders the close Sheet and closes a settled folio" do
      folio = create(:booking_folio, booking: booking, hotel: hotel)

      get hotel_folio_action_close_window_path(hotel, booking, folio), headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#folio_action_sheet dialog#folio-close-window-sheet")).to be_present
      expect(response.body).to include("Only settled folios with no pending charges can be closed.")

      post hotel_folio_action_close_window_path(hotel, booking, folio), params: { booking_folio: { reason: "Window no longer needed" } }

      expect(response).to redirect_to(folio_operations_path(booking, folio_id: folio.id))
      expect(folio.reload).to be_closed
    end

    it "renders the reopen Sheet and reopens a closed folio" do
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      ::Folios::Lifecycle::CloseFolio.call(folio: folio, user: user, reason: "Done")
      expect(folio.reload).to be_closed

      get hotel_folio_action_reopen_window_path(hotel, booking, folio), headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#folio_action_sheet dialog#folio-reopen-window-sheet")).to be_present

      post hotel_folio_action_reopen_window_path(hotel, booking, folio), params: { booking_folio: { reason: "Correction required" } }

      expect(response).to redirect_to(folio_operations_path(booking, folio_id: folio.id))
      expect(folio.reload).to be_open
    end

    it "offers Direct Bill when the folio is backed by a direct-bill account" do
      account = create(:hotel_corporate_account, :direct_bill, hotel: hotel)
      party = create(:booking_billing_party, :company, booking: booking, hotel: hotel, hotel_corporate_account: account)
      folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, booking_billing_party: party,
        payer_type: "company", hotel_corporate_account: account)
      create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 100)

      get hotel_folio_action_close_window_path(hotel, booking, folio), headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response.body).to include("Close this folio as Direct Bill and create an AR invoice.")
      expect(response.body).to include("Close as Direct Bill")
    end
  end

  describe "group scoping" do
    before { grant_permission("manage_folio_windows") }

    it "manages a folio window on a group child booking" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      folio = create(:booking_folio, booking: sibling, hotel: hotel, label: "Original Folio")

      get hotel_folio_action_edit_window_path(hotel, sibling, folio), headers: { "Turbo-Frame" => "folio_action_sheet" }
      expect(response).to have_http_status(:success)

      patch hotel_folio_action_edit_window_path(hotel, sibling, folio),
        params: { booking_folio: { label: "Updated Folio", folio_type: folio.folio_type, payer_type: folio.payer_type } }
      expect(folio.reload.label).to eq("Updated Folio")

      post hotel_folio_action_close_window_path(hotel, sibling, folio), params: { booking_folio: { reason: "Window no longer needed" } }
      expect(folio.reload).to be_closed

      post hotel_folio_action_reopen_window_path(hotel, sibling, folio), params: { booking_folio: { reason: "Correction required" } }
      expect(folio.reload).to be_open
    end

    it "rejects edit/close/reopen through a different booking in the same group" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      folio = create(:booking_folio, booking: sibling, hotel: hotel)

      get hotel_folio_action_edit_window_path(hotel, booking, folio), headers: { "Turbo-Frame" => "folio_action_sheet" }
      expect(response).to have_http_status(:not_found)

      patch hotel_folio_action_edit_window_path(hotel, booking, folio),
        params: { booking_folio: { label: "Hijacked", folio_type: folio.folio_type, payer_type: folio.payer_type } }
      expect(response).to have_http_status(:not_found)
      expect(folio.reload.label).not_to eq("Hijacked")

      post hotel_folio_action_close_window_path(hotel, booking, folio), params: { booking_folio: { reason: "Window no longer needed" } }
      expect(response).to have_http_status(:not_found)
      expect(folio.reload).to be_open

      post hotel_folio_action_reopen_window_path(hotel, booking, folio), params: { booking_folio: { reason: "Correction required" } }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "without manage_folio_windows" do
    it "forbids every window action" do
      folio = create(:booking_folio, booking: booking, hotel: hotel)

      [
        [ :get, hotel_folio_action_new_window_path(hotel, booking) ],
        [ :get, hotel_folio_action_edit_window_path(hotel, booking, folio) ],
        [ :get, hotel_folio_action_close_window_path(hotel, booking, folio) ],
        [ :get, hotel_folio_action_reopen_window_path(hotel, booking, folio) ]
      ].each do |verb, path|
        public_send(verb, path, headers: { "Turbo-Frame" => "folio_action_sheet" })
        expect(response).to have_http_status(:redirect), "expected #{path} to be refused"
        expect(flash[:alert]).to include("not authorized")
      end
    end

    it "does not create a folio window" do
      party = create(:booking_guest, booking: booking).booking_billing_party

      expect {
        post hotel_folio_action_new_window_path(hotel, booking), params: { folio_window: { booking_billing_party_id: party.id } }
      }.not_to change(BookingFolio, :count)

      expect(flash[:alert]).to include("not authorized")
    end
  end
end
