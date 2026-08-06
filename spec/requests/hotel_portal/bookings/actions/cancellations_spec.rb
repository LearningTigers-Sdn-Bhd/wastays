# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions cancellations", frozen_time: :business_day, type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Garden Suite") }
  let(:booking) do
    create(:booking, hotel: hotel, guest_name: "Ada Lovelace", status: "confirmed").tap do |record|
      create(:booking_room, booking: record, room_type: room_type, room_number: "101")
    end
  end

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

  describe "GET the cancellation form" do
    it "renders the cancellation Sheet in the primary frame" do
      get hotel_booking_action_cancel_booking_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("turbo-frame#booking_action_sheet dialog#booking-cancellation-sheet[data-controller='panels-ui--sheet']")

      expect(dialog).to be_present
      expect(dialog["data-panels-ui-sheet-side"]).to eq("right")
      expect(dialog.text).to include("Cancel booking", "Ada Lovelace", "Cancellation reason")
      expect(dialog.at_css("textarea[name='cancellation_reason'][required]")).to be_present
      expect(response.body).not_to include("<!DOCTYPE html>")
      expect(response.body).not_to include("offcanvas")
    end

    it "renders the group target selector for a group booking" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, status: "confirmed", guest_name: "Grace Hopper")
      create(:booking_room, booking: sibling, room_type: room_type, room_number: "102")

      get hotel_booking_action_cancel_booking_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("dialog#booking-cancellation-sheet")
      expect(dialog.css("input[name='booking_ids[]']")).not_to be_empty
      expect(dialog.at_css("input[name='target_scope']")).to be_present
    end

    it "renders into the secondary frame when launched stacked" do
      get hotel_booking_action_cancel_booking_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#booking_action_sheet_secondary dialog#booking-cancellation-sheet")).to be_present
    end
  end

  describe "the cancellation policy" do
    # The fee is a folio charge like any other, so posting it is gated on
    # post_folio_charges. A user who may cancel but not post charges gets a clear
    # refusal rather than a silently bypassed authorization check.
    before { grant_permission(role, "post_folio_charges") }

    def activate_cancellation_policy(pricing_type: "fixed", rate_value: 120)
      ReservationPolicies::EnsureDefaults.call(hotel)
      hotel.hotel_reservation_policies.find_by!(policy_type: "cancellation")
        .tap { |policy| policy.update!(active: true, pricing_type: pricing_type, rate_value: rate_value) }
    end

    it "shows the fee and the refund it leaves, with a waive option" do
      activate_cancellation_policy
      create(:deposit, hotel: hotel, booking: booking, amount: 200, status: "held")

      get hotel_booking_action_cancel_booking_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      dialog = Nokogiri::HTML(response.body).at_css("dialog#booking-cancellation-sheet")
      expect(dialog.text).to include("Cancellation policy", "Cancellation fee", "Refund due")
      expect(dialog.text).to include("120.00", "80.00")
      expect(dialog.at_css("input[type='radio'][name='charge_fee'][value='false']")).to be_present
    end

    it "renders policy applied per booking for a group sheet" do
      activate_cancellation_policy
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, status: "confirmed", guest_name: "Grace Hopper")
      create(:booking_room, booking: sibling, room_type: room_type, room_number: "102")

      get hotel_booking_action_cancel_booking_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(Nokogiri::HTML(response.body).at_css("dialog#booking-cancellation-sheet").text)
        .to include("Policy applied per booking")
    end

    it "posts the fee under the cancellation category when staff charge it" do
      activate_cancellation_policy

      post hotel_booking_action_cancel_booking_path(hotel, booking),
        params: { cancellation_reason: "Guest requested", charge_fee: "true" }

      expect(booking.reload.status).to eq("cancelled")
      charge = booking.booking_folio.folio_transactions.charge.find_by(category: "cancellation_charge")
      expect(charge.amount).to eq(120.0)
    end

    it "posts nothing when staff waive the fee" do
      activate_cancellation_policy

      post hotel_booking_action_cancel_booking_path(hotel, booking),
        params: { cancellation_reason: "Guest requested", charge_fee: "false" }

      expect(booking.reload.status).to eq("cancelled")
      expect(booking.booking_folio&.folio_transactions&.charge&.where(category: "cancellation_charge")).to be_blank
    end

    it "posts nothing when the policy is inactive, even if a fee is requested" do
      post hotel_booking_action_cancel_booking_path(hotel, booking),
        params: { cancellation_reason: "Guest requested", charge_fee: "true" }

      expect(booking.reload.status).to eq("cancelled")
      expect(booking.booking_folio&.folio_transactions&.charge&.where(category: "cancellation_charge")).to be_blank
    end

    # The fee posts inside the cancellation's own transaction, before the status
    # change, so a cancellation that fails never leaves an orphan fee behind.
    it "rolls the fee back when the cancellation itself fails" do
      activate_cancellation_policy
      allow(Bookings::TransitionStatus).to receive(:new).and_return(
        instance_double(Bookings::TransitionStatus, call: OpenStruct.new(success?: false, error: "Cannot cancel."))
      )

      post hotel_booking_action_cancel_booking_path(hotel, booking),
        params: { cancellation_reason: "Guest requested", charge_fee: "true" }

      expect(flash[:alert]).to eq("Cannot cancel.")
      expect(booking.reload.status).to eq("confirmed")
      expect(FolioTransaction.where(category: "cancellation_charge")).to be_empty
    end
  end

  describe "POST the cancellation" do
    it "cancels the booking and completes the sheet on a Turbo submission" do
      post hotel_booking_action_cancel_booking_path(hotel, booking),
        params: { cancellation_reason: "Guest requested" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).to include('target="booking_action_sheet"')
      expect(response.body).to include(CGI.escapeHTML(hotel_booking_workspace_path(hotel, booking, tab: "booking_details")))
      expect(booking.reload.status).to eq("cancelled")
    end

    it "redirects to the control panel on a direct request" do
      post hotel_booking_action_cancel_booking_path(hotel, booking),
        params: { cancellation_reason: "Guest requested" }

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))
      expect(flash[:notice]).to eq("Booking cancelled successfully.")
      expect(booking.reload.status).to eq("cancelled")
      expect(BookingAuditLog.where(auditable: booking, action_type: "cancel").last.metadata).to include(
        "reason" => "Guest requested"
      )
    end

    it "keeps the sheet open with an error when the reason is blank" do
      post hotel_booking_action_cancel_booking_path(hotel, booking),
        params: { cancellation_reason: "" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("dialog", "Cancellation reason is required.")
      expect(booking.reload.status).to eq("confirmed")
    end

    it "completes into the secondary frame when submitted stacked" do
      post hotel_booking_action_cancel_booking_path(hotel, booking),
        params: { cancellation_reason: "Guest requested" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet_secondary" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('target="booking_action_sheet_secondary"')
      expect(booking.reload.status).to eq("cancelled")
    end

    it "closes the sheet with a flash alert when the booking cannot be cancelled" do
      checked_in = create(:booking, hotel: hotel, status: "checked_in")

      post hotel_booking_action_cancel_booking_path(hotel, checked_in),
        params: { cancellation_reason: "Too late" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(flash[:alert]).to be_present
      expect(checked_in.reload.status).to eq("checked_in")
    end

    it "batch-cancels the selected group bookings" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, status: "confirmed", guest_name: "Grace Hopper")
      create(:booking_room, booking: sibling, room_type: room_type, room_number: "102")

      post hotel_booking_action_cancel_booking_path(hotel, booking),
        params: { cancellation_reason: "Event cancelled", target_scope: "group", booking_ids: [ booking.id, sibling.id ] },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(flash[:notice]).to eq("2 bookings cancelled.")
      expect(booking.reload.status).to eq("cancelled")
      expect(sibling.reload.status).to eq("cancelled")
    end

    it "cancels selected pending and overbooked group bookings" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      pending = create(:booking, hotel: hotel, group_booking: group, group_position: 1, status: "pending", guest_name: "Ada Lovelace")
      create(:booking_room, booking: pending, room_type: room_type, room_number: "101")
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, status: "overbooked", guest_name: "Grace Hopper")
      create(:booking_room, booking: sibling, room_type: room_type, room_number: "102")

      post hotel_booking_action_cancel_booking_path(hotel, pending),
        params: { cancellation_reason: "Group plans changed", target_scope: "individual", booking_ids: [ pending.id, sibling.id ] }

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, pending, tab: "booking_details"))
      expect(pending.reload.status).to eq("cancelled")
      expect(sibling.reload.status).to eq("cancelled")
    end

    it "blocks cancellation without manage_bookings permission" do
      role.role_permissions.destroy_all

      post hotel_booking_action_cancel_booking_path(hotel, booking),
        params: { cancellation_reason: "Guest requested" }

      expect(response).to have_http_status(:redirect)
      expect(booking.reload.status).to eq("confirmed")
    end

    it "does not find a booking from another hotel" do
      other_booking = create(:booking, hotel: other_hotel, status: "confirmed")

      post hotel_booking_action_cancel_booking_path(hotel, other_booking),
        params: { cancellation_reason: "Guest requested" }

      expect(response).to have_http_status(:not_found)
    end
  end
end
