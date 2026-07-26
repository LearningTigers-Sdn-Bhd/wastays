# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions booking creation", :business_day, type: :request do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: [ "101" ]) }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }

  def grant_permission(role, slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
    grant_permission(role, "manage_bookings")
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET the creation forms into the booking_action_sheet" do
    it "renders the full New Booking sheet" do
      get hotel_booking_action_new_booking_path(hotel), headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      frame = document.at_css("turbo-frame#booking_action_sheet")
      expect(frame).to be_present
      dialog = frame.at_css("dialog#booking-creation-sheet[data-controller='panels-ui--sheet']")
      expect(dialog).to be_present
      expect(dialog["data-panels-ui-sheet-side"]).to eq("bottom")
      expect(dialog.text).to include("New Booking", "Stay details", "Guest information")
      expect(dialog.at_css('[data-action="click->offcanvas#close"]')).to be_nil

      stay_window = dialog.at_css('[data-role="stay-window-fields"]')
      classification = dialog.at_css('[data-role="booking-classification-fields"]')
      expect(stay_window.parent["class"]).to include("md:grid-cols-2")
      expect(stay_window["class"]).to include("grid-cols-3")
      expect(stay_window.element_children.first["class"]).to include("col-span-2")
      expect(classification["class"]).to include("grid-cols-2")
      nights = stay_window.at_css('output[data-booking-room-rows-target="nights"]')
      expect(nights["class"]).to include("panel-input")
      expect(nights["aria-labelledby"]).to eq("booking_nights_label")

      guest_primary = dialog.at_css('[data-role="guest-primary-fields"]')
      guest_contacts = dialog.at_css('[data-role="guest-contact-fields"]')
      guest_demographics = dialog.at_css('[data-role="guest-demographic-fields"]')
      expect(guest_primary["class"]).to include("md:grid-cols-2")
      expect(guest_contacts["class"]).to include("md:grid-cols-2")
      expect(guest_demographics["class"]).to include("md:grid-cols-3")
      expect(guest_demographics.at_css('select[name="booking[guest_gender]"] option[value="female"]')).to be_present

      guest_autocompletes = dialog.css(".panel-autocomplete")
      expect(guest_autocompletes.size).to eq(3)
      expect(guest_autocompletes.map { |node| node.at_css("input")["name"] }).to contain_exactly(
        "booking[guest_name]", "booking[guest_email]", "booking[guest_phone]"
      )
      expect(dialog.at_css('input[name="booking[existing_guest_id]"]')).to be_present
      expect(dialog.at_css('input[name="booking[guest_update_intent]"][value="update_existing"]')).to be_present
      expect(dialog.at_css('[data-booking-guest-autofill-target="profileRow"]')["hidden"]).not_to be_nil
      expect(dialog.at_css('select[name="booking[rooms][0][room_number]"] option[value=""]').text).to eq("Select room later")
    end

    it "renders the Quick Booking sheet on the right" do
      return_to = hotel_stay_view_path(hotel, view: "timeline")
      get hotel_booking_action_quick_booking_path(hotel),
          params: { return_to:, source: "stay_view" },
          headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      dialog = Nokogiri::HTML(response.body).at_css("dialog#booking-creation-sheet")
      expect(dialog["data-panels-ui-sheet-side"]).to eq("right")
      expect(dialog.text).to include("Quick Booking")
      expect(dialog.css(".panel-autocomplete").size).to eq(3)
      expect(dialog.at_css('input[name="booking[existing_guest_id]"]')).to be_present
      expect(dialog.at_css('input[name="booking[guest_update_intent]"][value="update_existing"]')).to be_present
      profile_row = dialog.at_css('[data-booking-guest-autofill-target="profileRow"]')
      expect(profile_row["hidden"]).not_to be_nil
      expect(profile_row["class"]).not_to include("md:flex-row")
      expect(dialog.at_css('select[name="booking[rooms][0][room_number]"] option[value=""]').text).to eq("Select room later")
      more_options = dialog.at_css('a[data-controller="booking-form-transfer"]')
      expect(more_options.text.squish).to eq("More options")
      expect(more_options["data-action"]).to eq("booking-form-transfer#open")
      expect(more_options["data-booking-form-transfer-form-id-value"]).to eq("manual_booking_form")
      more_options_uri = URI.parse(more_options["href"])
      expect(more_options_uri.path).to eq(hotel_booking_action_new_booking_path(hotel))
      expect(Rack::Utils.parse_nested_query(more_options_uri.query)).to include(
        "return_to" => return_to,
        "source" => "stay_view"
      )
    end

    it "hydrates the full form from transferred Quick Booking values" do
      guest = create(:guest, created_by_hotel: hotel, name: "Existing Guest")
      get hotel_booking_action_new_booking_path(hotel), params: {
        booking: {
          check_in: "2026-08-01T14:00",
          check_out: "2026-08-03T11:00",
          guest_name: "Transferred Guest",
          guest_email: "transfer@example.com",
          guest_phone: "+60123456789",
          guest_country: "Malaysia",
          guest_gender: "female",
          guest_date_of_birth: "1992-03-04",
          existing_guest_id: guest.id,
          guest_update_intent: "update_existing",
          source: "whatsapp",
          rooms: {
            "0" => {
              room_type_id: room_type.id,
              room_number: "101",
              adults: "2",
              children: "1"
            }
          }
        }
      }, headers: { "Turbo-Frame" => "booking_action_sheet" }

      dialog = Nokogiri::HTML(response.body).at_css("dialog#booking-creation-sheet")
      expect(dialog.at_css('input[name="booking[guest_name]"]')["value"]).to eq("Transferred Guest")
      expect(dialog.at_css('input[name="booking[guest_email]"]')["value"]).to eq("transfer@example.com")
      expect(dialog.at_css('input[name="booking[existing_guest_id]"]')["value"]).to eq(guest.id.to_s)
      expect(dialog.at_css('input[name="booking[guest_update_intent]"][value="update_existing"]')["checked"]).not_to be_nil
      expect(dialog.at_css('[data-booking-room-rows-target="row"]')["data-preserved-room-number"]).to eq("101")
      expect(dialog.at_css('select[name="booking[rooms][0][room_type_id]"] option[selected]')["value"]).to eq(room_type.id.to_s)
    end

    it "renders a single server-rendered room row on demand" do
      room_type
      get room_row_hotel_bookings_path(hotel), params: { index: "3" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      row = document.at_css("[data-booking-room-rows-target='row']")
      expect(row).to be_present
      expect(row.at_css("[data-role='room-type'] select[name='booking[rooms][3][room_type_id]']")).to be_present
      expect(row.at_css("[data-role='rate-plan'] select")).to be_present
      popover = row.at_css("#booking-room-rate-breakdown-3")
      expect(popover["data-panels-ui--popover-trigger-on-value"]).to eq("hover")
      expect(popover.at_css("button[aria-label='Show rate breakdown'] svg")).to be_present
      expect(popover.at_css("[data-role='nightly-breakdown']")).to be_present
      expect(popover.at_css("[data-role='tax-breakdown']")).to be_present
      expect(popover.at_css("[data-role='breakdown-total']").text).to eq("MYR 0.00")
    end

    it "preselects the clicked room when opened from a stay-view cell or room card" do
      get hotel_booking_action_walk_in_check_in_path(hotel),
          params: { room_type_id: room_type.id, room_number: "101", source: "stay_view" },
          headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      row = Nokogiri::HTML(response.body).at_css("[data-booking-room-rows-target='row']")
      expect(row).to be_present
      expect(row["data-preserved-room-number"]).to eq("101")
      expect(row.at_css("[data-role='room-type'] select option[selected]")["value"]).to eq(room_type.id.to_s)
    end

    it "renders the Backdated Check-in sheet with the backdate fields" do
      get hotel_booking_action_backdated_check_in_path(hotel), headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Backdated Check-in")
      expect(response.body).to include("data-booking-room-rows-target=\"backdateFields\"")
    end

    it "renders the Walk-in Check-in sheet at full size" do
      get hotel_booking_action_walk_in_check_in_path(hotel), headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      dialog = Nokogiri::HTML(response.body).at_css("dialog#booking-creation-sheet")
      expect(dialog["data-panels-ui-sheet-side"]).to eq("bottom")
      expect(dialog.text).to include("Walk-in Check-in")
      expect(dialog.at_css('select[name="booking[rooms][0][room_number]"] option[value=""]').text).to eq("Select room")
    end
  end

  describe "POST creation" do
    let(:booking_params) do
      {
        guest_name: "New Guest",
        guest_email: "new-booking@example.com",
        guest_phone: "+60123456789",
        check_in: Date.current,
        check_out: Date.current + 1.day,
        adults: 1,
        guest_gender: "female",
        room_type_id: room_type.id,
        room_number: "101"
      }
    end

    it "creates a booking and redirects to its control panel on a direct request" do
      expect {
        post hotel_booking_action_new_booking_path(hotel), params: { booking: booking_params }
      }.to change(Booking, :count).by(1)

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, Booking.last))
      expect(flash[:notice]).to eq("Booking created successfully.")
      expect(Booking.last.guest_gender).to eq("female")
    end

    it "creates and immediately checks in a walk-in booking" do
      expect {
        post hotel_booking_action_walk_in_check_in_path(hotel), params: { booking: booking_params }
      }.to change(Booking, :count).by(1)

      expect(Booking.last).to be_checked_in
      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, Booking.last))
      expect(flash[:notice]).to eq("Walk-in guest checked in successfully.")
    end

    it "completes the sheet on a Turbo submission" do
      post hotel_booking_action_new_booking_path(hotel),
        params: { booking: booking_params },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).to include('target="booking_action_sheet"')
      expect(response.body).to include(CGI.escapeHTML(hotel_booking_workspace_path(hotel, Booking.last)))
    end

    it "re-renders the sheet form with errors when creation fails" do
      post hotel_booking_action_new_booking_path(hotel),
        params: { booking: booking_params.except(:room_type_id) },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('target="booking_action_sheet"')
      expect(response.body).to include("dialog")
      expect(response.body).to include("Each reservation row requires a room category.")
      expect(Booking.count).to eq(0)
    end

    it "re-renders the sheet form with a submitted date of birth without raising" do
      post hotel_booking_action_new_booking_path(hotel),
        params: { booking: booking_params.except(:room_type_id).merge(guest_date_of_birth: "1990-05-20") },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("1990-05-20")
      expect(Booking.count).to eq(0)
    end

    it "requires a backdate reason before creating a backdated booking" do
      post hotel_booking_action_backdated_check_in_path(hotel),
        params: { booking: booking_params, backdate_reason: "" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Backdated check-in reason is required.")
      expect(Booking.count).to eq(0)
    end

    it "creates a backdated walk-in with historical payment, charges, and audit metadata" do
      past_date = 1.day.ago.to_date
      create(:night_audit, hotel: hotel, business_date: past_date, status: "completed")
      create(:hotel_business_date, hotel: hotel, business_date: past_date, status: "closed")
      grant_permission(role, "post_folio_charges")
      grant_permission(role, "post_folio_payments")
      grant_permission(role, "override_financial_date_lock")

      expect {
        post hotel_booking_action_backdated_check_in_path(hotel), params: {
          booking: booking_params.merge(
            check_in: past_date,
            check_out: Date.current,
            record_payment: "1",
            payment_method: "cash",
            payment_amount: "250.00",
            backdate_reason: "Manual offline check-in"
          ),
          posting_date: past_date.to_s,
          retroactive_reason: "Router was down"
        }
      }.to change(Booking, :count).by(1)

      booking = Booking.last
      expect(booking).to be_checked_in
      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking))
      expect(booking.deposits.kind_prepayment.sole.received_at.to_date).to eq(past_date)
      expect(booking.booking_folio.folio_transactions.charge).to all(have_attributes(posting_date: past_date))
      expect(BookingAuditLog.where(auditable: booking, action_type: "check_in").last.metadata).to include(
        "backdate_reason_category" => "Manual offline check-in",
        "backdate_reason_details" => "Router was down"
      )
    end

    it "blocks creation without manage_bookings permission" do
      role.role_permissions.destroy_all

      post hotel_booking_action_new_booking_path(hotel), params: { booking: booking_params }

      expect(response).to have_http_status(:redirect)
    end
  end
end
