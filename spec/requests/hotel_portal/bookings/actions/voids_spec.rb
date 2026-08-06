# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions voids", frozen_time: :business_day, type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel:, guest_name: "Ada Lovelace", status: "confirmed") }

  def grant_permission(slug)
    permission = Permission.find_or_create_by!(slug:) { |record| record.name = slug.humanize }
    create(:role_permission, role:, permission:)
  end

  before do
    BusinessDates::ResetAuthority.call!(hotel:, date: Date.current)
    %w[view_bookings manage_bookings void_bookings].each { |slug| grant_permission(slug) }
    create(:user_hotel_access, user:, hotel:, role:)
    sign_in_as(user)
  end

  it "renders a destructive Sheet that explains folios are unchanged" do
    get hotel_booking_action_void_booking_path(hotel, booking),
      headers: { "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    dialog = document.at_css("turbo-frame#booking_action_sheet dialog#booking-void-sheet[data-controller='panels-ui--sheet']")
    expect(dialog).to be_present
    expect(dialog.text).to include("Void booking", "Existing folios, charges, payments, deposits, and invoices will not be changed")
    expect(dialog.at_css("textarea[name='void_reason'][required]")).to be_present
  end

  it "voids the booking and preserves the folio" do
    folio = create(:booking_folio, booking:, hotel:, status: "open")
    transaction = create(:folio_transaction, booking_folio: folio, amount: 125)

    post hotel_booking_action_void_booking_path(hotel, booking),
      params: { void_reason: "Duplicate reservation" }

    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))
    expect(flash[:notice]).to eq("Booking voided. Existing folios were left unchanged.")
    expect(booking.reload.status).to eq("voided")
    expect(folio.reload).to be_open
    expect(transaction.reload.amount).to eq(125)
  end

  it "keeps the Sheet open when the reason is blank" do
    post hotel_booking_action_void_booking_path(hotel, booking),
      params: { void_reason: "" },
      headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Void reason is required.")
    expect(booking.reload.status).to eq("confirmed")
  end

  it "batch-voids selected group bookings with mixed lifecycle statuses" do
    group = create(:group_booking, hotel:, name: "Conference Group")
    booking.update!(group_booking: group, group_position: 1)
    completed = create(:booking, hotel:, group_booking: group, group_position: 2, status: "completed")
    closed_folio = create(:booking_folio, booking: completed, hotel:, status: "closed", closed_at: 1.day.ago, closed_by: user)

    post hotel_booking_action_void_booking_path(hotel, booking),
      params: {
        void_reason: "Duplicate group reservation",
        target_scope: "group",
        booking_ids: [ booking.id, completed.id ]
      }

    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))
    expect(booking.reload.status).to eq("voided")
    expect(completed.reload.status).to eq("voided")
    expect(closed_folio.reload).to be_closed
  end

  it "requires the dedicated void_bookings permission" do
    role.role_permissions.joins(:permission).find_by!(permissions: { slug: "void_bookings" }).destroy!

    post hotel_booking_action_void_booking_path(hotel, booking), params: { void_reason: "Duplicate" }

    expect(response).to have_http_status(:redirect)
    expect(booking.reload.status).to eq("confirmed")
  end

  it "does not find bookings from another hotel" do
    other_booking = create(:booking, hotel: other_hotel, status: "confirmed")

    post hotel_booking_action_void_booking_path(hotel, other_booking), params: { void_reason: "Duplicate" }

    expect(response).to have_http_status(:not_found)
  end

  it "shows the action to authorized users and a persistent warning after voiding" do
    get hotel_booking_workspace_path(hotel, booking)
    expect(response.body).to include("Void booking", hotel_booking_action_void_booking_path(hotel, booking))

    Bookings::VoidBooking.call(booking:, user:, reason: "Duplicate reservation")
    get hotel_booking_workspace_path(hotel, booking)

    expect(response.body).to include("This booking has been voided")
    expect(response.body).to include("Existing folios were left unchanged")
    expect(response.body).not_to include(hotel_booking_action_void_booking_path(hotel, booking))
  end
end
