# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel AR invoice show tabs", type: :system, js: true do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:user) { create(:user, account: account, email: "ar-show@example.com") }
  let(:role) { create(:role, account: account) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, direct_bill_enabled: true) }
  let(:booking) { create(:booking, hotel: hotel, confirmation_token: "BK-AR-TABS") }
  let(:folio) do
    create(
      :booking_folio,
      :secondary,
      booking: booking,
      hotel: hotel,
      folio_number: 720,
      hotel_corporate_account: relationship
    )
  end
  let!(:invoice) do
    create(
      :ar_invoice,
      hotel: hotel,
      booking_folio: folio,
      hotel_corporate_account: relationship,
      metadata: { booking_id: booking.id, direct_bill_closed_at: "2026-06-01T00:15:00Z" }
    )
  end

  before do
    role.permissions << Permission.find_or_create_by!(slug: "view_reports") { |record| record.name = "View reports" }
    role.permissions << Permission.find_or_create_by!(slug: "manage_ar_payments") { |record| record.name = "Manage AR Payments" }
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_through_ui(user)
  end

  it "switches between payment allocations and technical snapshots and persists the selected tab" do
    visit hotel_ar_invoice_path(hotel, invoice)

    expect(page).to have_css("[data-testid='payment-allocations-panel']")
    expect(page).to have_css("[data-testid='technical-snapshots-panel']", visible: :hidden)

    click_button "Technical Snapshots"

    expect(page).to have_current_path(hotel_ar_invoice_path(hotel, invoice, tab: "technical-snapshots"))
    expect(page).to have_css("[data-testid='technical-snapshots-panel']")
    expect(page).to have_css("[data-testid='payment-allocations-panel']", visible: :hidden)
    expect(page).to have_text("DIRECT BILL CLOSED AT")

    click_button "Payment Allocations"

    expect(page).to have_current_path(hotel_ar_invoice_path(hotel, invoice, tab: "payment-allocations"))
    expect(page).to have_css("[data-testid='payment-allocations-panel']")
    expect(page).to have_css("[data-testid='technical-snapshots-panel']", visible: :hidden)
  end
end
