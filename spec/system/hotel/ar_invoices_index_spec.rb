# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel AR invoices index", type: :system, js: true do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:user) { create(:user, account: account, email: "ar-manager@example.com") }
  let(:role) { create(:role, account: account) }
  let(:relationship) { create(:hotel_corporate_account, :direct_bill, hotel: hotel) }
  let(:booking) { create(:booking, hotel: hotel, confirmation_token: "BK-AR-ROW") }
  let(:folio) do
    create(
      :booking_folio,
      :secondary,
      booking: booking,
      hotel: hotel,
      folio_number: 610,
      hotel_corporate_account: relationship
    )
  end
  let!(:invoice) do
    create(
      :ar_invoice,
      hotel: hotel,
      booking_folio: folio,
      hotel_corporate_account: relationship,
      amount: 250,
      paid_amount: 0,
      outstanding_amount: 250,
      currency: "MYR"
    )
  end

  before do
    %w[view_reports view_bookings manage_ar_payments].each do |slug|
      role.permissions << Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    end
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_through_ui(user)
  end

  it "opens the invoice from the desktop row and keeps dropdown navigation independent" do
    page.current_window.resize_to(1440, 1000)
    visit hotel_ar_invoices_path(hotel)

    find("[data-testid='ar-invoice-row-#{invoice.id}']").click
    expect(page).to have_current_path(hotel_ar_invoice_path(hotel, invoice))

    visit hotel_ar_invoices_path(hotel)
    find("[data-testid='ar-invoice-actions-#{invoice.id}']", visible: true).click
    within(find("body > [data-dropdown-target='menu']", visible: true)) do
      click_link "View Booking"
    end

    expect(page).to have_current_path(hotel_booking_control_panel_path(hotel, booking, tab: "booking_details"))
  end

  it "opens the invoice when the mobile card is tapped or keyboard-activated" do
    page.current_window.resize_to(390, 844)
    visit hotel_ar_invoices_path(hotel)

    card = find("[data-testid='ar-invoice-card-#{invoice.id}']")
    card.send_keys(:enter)

    expect(page).to have_current_path(hotel_ar_invoice_path(hotel, invoice))

    visit hotel_ar_invoices_path(hotel)
    find("[data-testid='ar-invoice-card-#{invoice.id}']").click

    expect(page).to have_current_path(hotel_ar_invoice_path(hotel, invoice))
  end
end
