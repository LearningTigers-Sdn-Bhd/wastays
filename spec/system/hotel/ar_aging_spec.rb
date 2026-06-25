# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel AR aging", type: :system, js: true do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:user) { create(:user, account: account, email: "aging-manager@example.com") }
  let(:role) { create(:role, account: account) }
  let(:relationship) do
    create(
      :hotel_corporate_account,
      hotel: hotel,
      direct_bill_enabled: true,
      corporate_account: create(:account, :corporate, name: "Atlas Holdings")
    )
  end
  let(:booking) { create(:booking, hotel: hotel, confirmation_token: "BK-AGING-ROW") }
  let(:folio) do
    create(
      :booking_folio,
      :secondary,
      booking: booking,
      hotel: hotel,
      folio_number: 620,
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
      currency: "MYR",
      due_on: hotel.current_business_date - 10.days
    )
  end

  before do
    role.permissions << Permission.find_or_create_by!(slug: "view_reports") { |record| record.name = "View Reports" }
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_through_ui(user)
  end

  it "opens filtered outstanding invoices from the desktop row" do
    page.current_window.resize_to(1440, 1000)
    visit hotel_ar_aging_path(hotel)

    find("[data-testid='aging-row-#{relationship.id}-MYR']").click

    expect(page).to have_current_path(
      hotel_ar_invoices_path(hotel, hotel_corporate_account_id: relationship.id, balance: "outstanding")
    )
    expect(page).to have_content("OUTSTANDING ONLY")
    expect(page).to have_content("BK-AGING-ROW")
  end

  it "opens filtered outstanding invoices when the mobile card is keyboard-activated" do
    page.current_window.resize_to(390, 844)
    visit hotel_ar_aging_path(hotel)

    find("[data-testid='aging-card-#{relationship.id}-MYR']").send_keys(:enter)

    expect(page).to have_current_path(
      hotel_ar_invoices_path(hotel, hotel_corporate_account_id: relationship.id, balance: "outstanding")
    )
  end
end
