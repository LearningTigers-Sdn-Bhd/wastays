# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel AR statements", type: :system, js: true do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "live") }
  let(:user) { create(:user, account: account, email: "ar-manager@example.com") }
  let(:role) { create(:role, account: account) }
  let(:relationship) do
    create(
      :hotel_corporate_account,
      hotel: hotel,
      corporate_account: create(:account, :corporate, name: "Atlas Travel"),
      credit_currency: "MYR"
    )
  end

  before do
    role.permissions << Permission.find_or_create_by!(slug: "view_reports") { |record| record.name = "View Reports" }
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    allow_any_instance_of(Hotel).to receive(:current_business_date).and_return(Date.new(2026, 6, 30))
    create_invoice(currency: "MYR", amount: 100, token: "MYR-STATEMENT")
    create_invoice(currency: "USD", amount: 75, token: "USD-STATEMENT")
    sign_in_through_ui(user)
  end

  it "opens an account statement and auto-submits the currency selector" do
    visit hotel_ar_statements_path(hotel)
    within("[data-testid='ar-statement-row-#{relationship.id}']") do
      click_link "View"
    end

    expect(page).to have_content("MYR 100.00")

    select "USD", from: "Currency"

    expect(page).to have_content("USD 75.00")
    expect(page).not_to have_content("MYR 100.00")
    click_button "Download PDF"
    expect(page).to have_link("Summary", href: /currency=USD/)
  end

  def create_invoice(currency:, amount:, token:)
    booking = create(:booking, hotel: hotel, confirmation_token: token, currency: currency)
    folio = create(
      :booking_folio,
      :secondary,
      booking: booking,
      hotel: hotel,
      hotel_corporate_account: relationship,
      currency: currency
    )
    create(
      :ar_invoice,
      hotel: hotel,
      booking_folio: folio,
      hotel_corporate_account: relationship,
      amount: amount,
      outstanding_amount: amount,
      currency: currency,
      issued_on: Date.new(2026, 6, 5),
      due_on: Date.new(2026, 7, 5)
    )
  end
end
