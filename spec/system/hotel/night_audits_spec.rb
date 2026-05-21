require "rails_helper"

RSpec.describe "Hotel night audits", type: :system do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "hotel_staff", email: "frontdesk@example.com") }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }
  let!(:permission) do
    Permission.find_or_create_by!(slug: "manage_night_audit") do |record|
      record.name = "Manage Night Audit"
    end
  end

  context "with rack_test driver" do
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
      # Freeze time to 10 AM to ensure we are well past the business day end (2 AM)
      # and into a clearly closable business date.
      travel_to Time.zone.local(2026, 5, 19, 10, 0, 0)
      business_date = hotel.latest_closable_business_date

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

      perform_enqueued_jobs do
        within("[data-testid='manual-night-audit-form']") do
          fill_in "Notes", with: "Front desk close"
          click_button "Run Audit"
        end
      end

      expect(page).to have_content("Night audit has been scheduled in the background. Please wait while it processes.")
      expect(page).to have_content("Night Audit #{business_date.strftime('%d %b %Y')}")
      expect(page).to have_content("Completed")
      expect(page).to have_content("Financial Summary")
    end

    it "shows blockers on the result page" do
      travel_to Time.zone.local(2026, 5, 23, 10, 0, 0)
      business_date = Date.new(2026, 5, 22)

      create(:booking,
        hotel: hotel,
        status: "checked_in",
        payment_status: "captured",
        guest_name: "Aisha Tan",
        confirmation_token: "WS-BLOCK-001",
        check_in: business_date - 1.day,
        check_out: business_date,
        checked_in_at: 1.day.ago)

      visit hotel_night_audits_path(hotel)

      perform_enqueued_jobs do
        within("[data-testid='manual-night-audit-form']") do
          fill_in "Business Date", with: business_date.to_s
          click_button "Run Audit"
        end
      end

      expect(page).to have_content("Night audit has been scheduled in the background. Please wait while it processes.")
      expect(page).to have_content("Audit Blockers")
      expect(page).to have_content("Aisha Tan")
      expect(page).to have_content("Due out today but still not checked out")
    end
  end

  context "with cuprite driver", js: true do
    before do
      driven_by(:cuprite)

      role.permissions << permission
      UserRole.create!(user: user, role: role)
      UserHotelAccess.create!(user: user, hotel: hotel, role: role)

      visit login_path
      fill_in "Email Address", with: user.email
      fill_in "Password", with: "password123"
      click_button "Sign In to Portal"
    end

    it "navigates to the resolve page and displays blockers interactive wizard" do
      travel_to Time.zone.local(2026, 5, 23, 10, 0, 0)
      business_date = Date.new(2026, 5, 22)

      create(:booking,
        hotel: hotel,
        status: "checked_in",
        payment_status: "captured",
        guest_name: "Aisha Tan",
        confirmation_token: "WS-BLOCK-001",
        check_in: business_date - 1.day,
        check_out: business_date,
        checked_in_at: 1.day.ago)

      visit hotel_night_audits_path(hotel)

      perform_enqueued_jobs do
        within("[data-testid='manual-night-audit-form']") do
          fill_in "Business Date", with: business_date.to_s
          click_button "Run Audit"
        end
      end

      expect(page).to have_content("BLOCKED")
      expect(page).to have_content("Resolve Blockers")
      click_link "Resolve Blockers"

      expect(page).to have_content("Resolve Audit Blockers")
      expect(page).to have_content("Due Outs Not Checked Out")
      expect(page).to have_content("Aisha Tan")
    end
  end
end
