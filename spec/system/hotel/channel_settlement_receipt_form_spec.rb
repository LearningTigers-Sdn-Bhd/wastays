# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OTA settlement receipt form", type: :system, js: true do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:, status: "live") }
  let(:user) { create(:user, account:, email: "ota-receipt@example.com") }
  let(:role) { create(:role, account:) }
  let(:source) { create(:booking_source, kind: "ota", label: "Booking Test") }
  let(:settlement) do
    create(:channel_settlement,
      hotel:, booking_source: source, currency: "MYR", channel_manager_reference: "OTA-LIVE-1")
  end
  let!(:allocation) do
    create(:channel_settlement_allocation,
      channel_settlement: settlement, currency: "MYR", expected_net_amount: 90)
  end

  before do
    role.permissions << Permission.find_or_create_by!(slug: "view_reports") { |record| record.name = "View reports" }
    role.permissions << Permission.find_or_create_by!(slug: "manage_ar_payments") { |record| record.name = "Manage AR Payments" }
    create(:user_hotel_access, user:, hotel:, role:)
    create(:hotel_payment_method, hotel:)
    sign_in_through_ui(user)
  end

  it "updates live totals, warns about overpayment, and filters the scoped rows" do
    visit new_hotel_channel_settlement_receipt_path(hotel)

    fill_in "Receipt amount", with: "100.00"
    fill_in "Amount allocated to OTA-LIVE-1", with: "95.00"

    expect(page).to have_css('[data-ota-receipt-form-target="allocated"]', text: "MYR 95.00")
    expect(page).to have_css('[data-ota-receipt-form-target="remaining"]', text: "MYR 5.00")
    expect(page).to have_text("Overpayment entered")

    fill_in "Search allocations", with: "does-not-match"

    expect(page).to have_css('tr[data-search-text*="ota-live-1"]', visible: :hidden)
    expect(page).to have_text("No allocations match your search.")
  end
end
