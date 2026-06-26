# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel AR payments index", type: :system, js: true do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:user) { create(:user, account: account, email: "ar-payment-manager@example.com") }
  let(:role) { create(:role, account: account) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel) }
  let!(:payment) { create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 250, reference_number: "BANK-SYSTEM-1") }

  before do
    %w[view_reports manage_ar_payments].each do |slug|
      role.permissions << Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    end
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_through_ui(user)
  end

  it "opens payment detail from desktop rows and mobile cards" do
    page.current_window.resize_to(1440, 1000)
    visit hotel_ar_payments_path(hotel)

    find("[data-testid='ar-payment-row-#{payment.id}']").click
    expect(page).to have_current_path(hotel_ar_payment_path(hotel, payment))

    page.current_window.resize_to(390, 844)
    visit hotel_ar_payments_path(hotel)

    find("[data-testid='ar-payment-card-#{payment.id}']").send_keys(:enter)
    expect(page).to have_current_path(hotel_ar_payment_path(hotel, payment))
  end
end
