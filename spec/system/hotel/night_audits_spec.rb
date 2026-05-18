require "rails_helper"

RSpec.describe "Hotel night audits", type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "hotel_staff", email: "frontdesk@example.com") }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }
  let!(:permission) do
    Permission.find_or_create_by!(slug: "manage_night_audit") do |record|
      record.name = "Manage Night Audit"
    end
  end

  before do
    driven_by(:rack_test)

    role.permissions << permission
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    visit login_path
    fill_in "Email Address", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In to Portal"
  end

  it "renders the page and lets front desk run a completed audit" do
    business_date = Time.use_zone(User::DEFAULT_TIME_ZONE) { Date.current - 1.day }

    booking = create(:booking,
      hotel: hotel,
      status: "completed",
      payment_status: "captured",
      check_in: business_date - 1.day,
      check_out: business_date,
      checked_in_at: 1.day.ago,
      checked_out_at: Time.current)
    folio = create(:booking_folio, hotel: hotel, booking: booking)
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 200.0, posting_date: business_date - 1.day)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 200.0, posting_date: business_date)

    visit hotel_night_audits_path(hotel)

    expect(page).to have_content("Night Audit")
    expect(page).to have_content("Manual Run")
    expect(page).to have_link("Night Audit", href: hotel_night_audits_path(hotel))
    expect(page).to have_field("Business Date", with: business_date.strftime("%Y-%m-%d"))

    within("[data-testid='manual-night-audit-form']") do
      fill_in "Notes", with: "Front desk close"
      click_button "Run Audit"
    end

    expect(page).to have_content("Night audit completed successfully.")
    expect(page).to have_content("Night Audit #{business_date.strftime('%d %b %Y')}")
    expect(page).to have_content("Completed")
    expect(page).to have_content("Payment Summary")
  end

  it "shows blockers on the result page" do
    today_kl = Time.use_zone(User::DEFAULT_TIME_ZONE) { Date.current }
    create(:booking,
      hotel: hotel,
      status: "checked_in",
      payment_status: "captured",
      guest_name: "Aisha Tan",
      confirmation_token: "WS-BLOCK-001",
      check_in: today_kl - 1.day,
      check_out: today_kl,
      checked_in_at: 1.day.ago)

    visit hotel_night_audits_path(hotel)

    within("[data-testid='manual-night-audit-form']") do
      fill_in "Business Date", with: today_kl.to_s
      click_button "Run Audit"
    end

    expect(page).to have_content("Night audit completed with blockers.")
    expect(page).to have_content("Blocked Details")
    expect(page).to have_content("Aisha Tan")
    expect(page).to have_content("Due out today but still not checked out")
  end
end
