# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions late checkouts", :business_day, type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Garden Suite", room_number_mode: "custom", room_numbers: %w[101 102 103]) }
  let(:booking) do
    create(:booking, hotel: hotel, guest_name: "Ada Lovelace", status: "review_due_out", check_in: Date.yesterday, check_out: Date.current).tap do |record|
      create(:booking_room, booking: record, room_type: room_type, room_number: "101")
      create(:booking_folio, booking: record, hotel: hotel, status: "open")
    end
  end

  def grant_permission(role, slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  def create_group_child(group, position:, room_number:, guest_name:)
    create(:booking, hotel: hotel, group_booking: group, group_position: position, status: "review_due_out", guest_name: guest_name, check_in: Date.yesterday, check_out: Date.current).tap do |record|
      create(:booking_room, booking: record, room_type: room_type, room_number: room_number)
      create(:booking_folio, booking: record, hotel: hotel, status: "open")
    end
  end

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
    grant_permission(role, "manage_bookings")
    grant_permission(role, "post_folio_charges")
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET the late-checkout form" do
    it "renders the late-checkout Sheet with the charge form in the primary frame" do
      get hotel_booking_action_late_checkout_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("turbo-frame#booking_action_sheet dialog#booking-late-checkout-sheet[data-controller='panels-ui--sheet']")

      expect(dialog).to be_present
      expect(dialog["data-panels-ui-sheet-side"]).to eq("right")
      expect(dialog.text).to include("Review late checkout", "Ada Lovelace", "Charge calculation")
      expect(dialog.at_css("[data-controller='booking-actions--late-checkout']")).to be_present
      expect(dialog.at_css("input[type='radio'][name='charge_type']")).to be_present
      expect(dialog.at_css("input[name='check_out']")).to be_present
      expect(response.body).not_to include("<!DOCTYPE html>")
      expect(response.body).not_to include("offcanvas")
    end

    it "renders the group target selector for a group booking" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      create_group_child(group, position: 2, room_number: "102", guest_name: "Grace Hopper")

      get hotel_booking_action_late_checkout_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("dialog#booking-late-checkout-sheet")
      expect(dialog.css("input[name='booking_ids[]']")).not_to be_empty
      expect(dialog.at_css("input[name='target_scope']")).to be_present
    end

    it "renders into the secondary frame when launched stacked" do
      get hotel_booking_action_late_checkout_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#booking_action_sheet_secondary dialog#booking-late-checkout-sheet")).to be_present
    end
  end

  describe "POST the late-checkout review" do
    it "applies the charge and completes the sheet on a Turbo submission" do
      post hotel_booking_action_late_checkout_path(hotel, booking),
        params: { charge_type: "charge", charge_calculation: "standard", amount: "50.00", check_out: booking.check_out.strftime("%Y-%m-%dT%H:%M") },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).to include('target="booking_action_sheet"')
      expect(booking.reload.status).to eq("checked_in")
      expect(flash[:notice]).to eq("Late checkout charge applied.")
    end

    it "rejects late checkout and moves the booking to checkout_required" do
      post hotel_booking_action_late_checkout_path(hotel, booking),
        params: { charge_type: "none" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(booking.reload.status).to eq("checkout_required")
      expect(flash[:notice]).to eq("Late checkout rejected. Complete checkout to resolve the booking.")
    end

    it "redirects to the control panel on a direct request" do
      post hotel_booking_action_late_checkout_path(hotel, booking),
        params: { charge_type: "charge", charge_calculation: "standard", amount: "50.00", check_out: booking.check_out.strftime("%Y-%m-%dT%H:%M") }

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))
      expect(flash[:notice]).to eq("Late checkout charge applied.")
      expect(booking.reload.status).to eq("checked_in")
    end

    it "completes into the secondary frame when submitted stacked" do
      post hotel_booking_action_late_checkout_path(hotel, booking),
        params: { charge_type: "none" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet_secondary" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('target="booking_action_sheet_secondary"')
    end

    it "closes the sheet with a flash alert when processing fails" do
      allow(Bookings::ProcessLateCheckout).to receive(:call).and_return(OpenStruct.new(success?: false, error: "Late checkout could not be processed."))

      post hotel_booking_action_late_checkout_path(hotel, booking),
        params: { charge_type: "charge", amount: "50.00" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(flash[:alert]).to eq("Late checkout could not be processed.")
    end

    it "batch-resolves the selected group bookings" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      sibling = create_group_child(group, position: 2, room_number: "102", guest_name: "Grace Hopper")

      post hotel_booking_action_late_checkout_path(hotel, booking),
        params: { target_scope: "individual", booking_ids: [ booking.id, sibling.id ], charge_type: "charge", charge_calculation: "standard", amount: "50.00", check_out: booking.check_out.strftime("%Y-%m-%dT%H:%M") },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(flash[:notice]).to eq("2 bookings resolved for late checkout.")
      expect(booking.reload.status).to eq("checked_in")
      expect(sibling.reload.status).to eq("checked_in")
    end

    it "blocks late checkout without manage_bookings permission" do
      role.role_permissions.destroy_all

      post hotel_booking_action_late_checkout_path(hotel, booking),
        params: { charge_type: "none" }

      expect(response).to have_http_status(:redirect)
      expect(booking.reload.status).to eq("review_due_out")
    end

    it "does not find a booking from another hotel" do
      other_booking = create(:booking, hotel: other_hotel, status: "review_due_out")

      post hotel_booking_action_late_checkout_path(hotel, other_booking),
        params: { charge_type: "none" }

      expect(response).to have_http_status(:not_found)
    end
  end
end
