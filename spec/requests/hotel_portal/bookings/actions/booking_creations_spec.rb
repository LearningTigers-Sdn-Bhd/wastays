# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions booking creation", type: :request do
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
    end

    it "renders the Quick Booking sheet on the right" do
      get hotel_booking_action_quick_booking_path(hotel), headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      dialog = Nokogiri::HTML(response.body).at_css("dialog#booking-creation-sheet")
      expect(dialog["data-panels-ui-sheet-side"]).to eq("right")
      expect(dialog.text).to include("Quick Booking")
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
        room_type_id: room_type.id,
        room_number: "101"
      }
    end

    it "creates a booking and redirects to its control panel on a direct request" do
      expect {
        post hotel_booking_action_new_booking_path(hotel), params: { booking: booking_params }
      }.to change(Booking, :count).by(1)

      expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, Booking.last))
      expect(flash[:notice]).to eq("Booking created successfully.")
    end

    it "creates and immediately checks in a walk-in booking" do
      expect {
        post hotel_booking_action_walk_in_check_in_path(hotel), params: { booking: booking_params }
      }.to change(Booking, :count).by(1)

      expect(Booking.last).to be_checked_in
      expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, Booking.last))
      expect(flash[:notice]).to eq("Walk-in guest checked in successfully.")
    end

    it "completes the sheet on a Turbo submission" do
      post hotel_booking_action_new_booking_path(hotel),
        params: { booking: booking_params },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).to include('target="booking_action_sheet"')
      expect(response.body).to include(CGI.escapeHTML(hotel_booking_control_panel_path(hotel, Booking.last)))
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
            payment_amount: "250.00"
          ),
          posting_date: past_date.to_s,
          backdate_reason: "Manual offline check-in",
          retroactive_reason: "Router was down"
        }
      }.to change(Booking, :count).by(1)

      booking = Booking.last
      expect(booking).to be_checked_in
      expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking))
      expect(booking.payment_transactions.last.captured_at.to_date).to eq(past_date)
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
