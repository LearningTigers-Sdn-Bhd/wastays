# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions no-show folio repairs", frozen_time: :business_day, type: :request do
  let(:hotel) { create(:hotel, status: "live") }
  let(:other_hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "Ada Lovelace", status: "no_show", currency: "MYR") }
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel) }

  def grant_permission(role, slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  def create_no_show_tourism_tax(amount:, folio: self.folio)
    create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: :charge,
      category: "tax",
      amount: amount,
      metadata: {
        posting_source: "no_show",
        tax_line: { type: "tourism_tax", name: "Tourism Tax", amount: amount.to_s }
      }
    )
  end

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
    grant_permission(role, "manage_bookings")
    grant_permission(role, "post_folio_corrections")
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET the repair form" do
    it "renders the repair Sheet with the tourism-tax preview in the primary frame" do
      create_no_show_tourism_tax(amount: 10)

      get hotel_booking_action_repair_no_show_folio_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("turbo-frame#booking_action_sheet dialog#booking-no-show-folio-repair-sheet[data-controller='panels-ui--sheet']")

      expect(dialog).to be_present
      expect(dialog["data-panels-ui-sheet-side"]).to eq("right")
      expect(dialog.text).to include("Repair no-show folio", "Ada Lovelace", "Tourism tax to remove")
      expect(dialog.at_css("input[type='submit'], button[type='submit']")).to be_present
      expect(response.body).not_to include("<!DOCTYPE html>")
      expect(response.body).not_to include("offcanvas")
    end

    it "renders an informational state with no submit when there is nothing to repair" do
      get hotel_booking_action_repair_no_show_folio_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("dialog#booking-no-show-folio-repair-sheet")
      expect(dialog.text).to include("no no-show tourism tax to repair")
      expect(dialog.at_css("input[type='submit']")).to be_nil
    end

    it "renders into the secondary frame when launched stacked" do
      create_no_show_tourism_tax(amount: 10)

      get hotel_booking_action_repair_no_show_folio_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#booking_action_sheet_secondary dialog#booking-no-show-folio-repair-sheet")).to be_present
    end
  end

  describe "POST the repair" do
    it "reverses the tourism tax and completes the sheet on a Turbo submission" do
      tourism_tax = create_no_show_tourism_tax(amount: 10)

      post hotel_booking_action_repair_no_show_folio_path(hotel, booking),
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).to include('target="booking_action_sheet"')
      expect(tourism_tax.reload).to be_reversed
    end

    it "redirects to the control panel with the repair notice on a direct request" do
      create_no_show_tourism_tax(amount: 10)

      post hotel_booking_action_repair_no_show_folio_path(hotel, booking)

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))
      expect(flash[:notice]).to include("Tourism tax of MYR 10.00 was removed from the no-show folio.")
    end

    it "reports the idempotent outcome when there is nothing to repair" do
      post hotel_booking_action_repair_no_show_folio_path(hotel, booking)

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))
      expect(flash[:notice]).to eq("No-show folio already has no tourism tax to repair.")
    end

    it "completes into the secondary frame when submitted stacked" do
      create_no_show_tourism_tax(amount: 10)

      post hotel_booking_action_repair_no_show_folio_path(hotel, booking),
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet_secondary" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('target="booking_action_sheet_secondary"')
    end
  end

  describe "authorization" do
    it "blocks repair without the post_folio_corrections permission" do
      RolePermission.joins(:permission).where(role: role, permissions: { slug: "post_folio_corrections" }).destroy_all

      get hotel_booking_action_repair_no_show_folio_path(hotel, booking)

      expect(response).to have_http_status(:redirect)
    end

    it "blocks repair without the manage_bookings permission" do
      RolePermission.joins(:permission).where(role: role, permissions: { slug: "manage_bookings" }).destroy_all

      get hotel_booking_action_repair_no_show_folio_path(hotel, booking)

      expect(response).to have_http_status(:redirect)
    end

    it "does not find a booking from another hotel" do
      other_booking = create(:booking, hotel: other_hotel, status: "no_show")

      get hotel_booking_action_repair_no_show_folio_path(hotel, other_booking)

      expect(response).to have_http_status(:not_found)
    end
  end
end
