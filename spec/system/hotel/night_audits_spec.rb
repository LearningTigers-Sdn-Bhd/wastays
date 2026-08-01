require "rails_helper"

RSpec.describe "Hotel night audits", type: :system do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "hotel_staff", email: "frontdesk@example.com") }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account: account, plan: plan, status: "approved") }
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
      create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "no_show_auto_handling"), enabled: true)

      sign_in_through_ui(user)
    end

    it "renders the page and lets front desk run a completed audit" do
      # Freeze time to 10 AM to ensure we are well past the business day end (2 AM)
      # and into a clearly closable business date.
      with_frozen_time Time.zone.local(2026, 5, 19, 10, 0, 0)
      business_date = hotel.latest_closable_business_date
      BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)

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

      expect(page).to have_content("Business Date Control Center")
      expect(page).to have_content("Close Readiness")
      expect(page).to have_content("Audit Action")
      expect(page).to have_content("Current Business Date")
      expect(page).to have_content("Calendar Date")
      expect(page).to have_content("Finished At")
      within("[data-testid='night-audit-page-header']") do
        expect(page).to have_no_css("[data-testid='business-date-status']")
      end
      within("[data-testid='business-date-card']") do
        expect(page).to have_content("Accounting authority")
        expect(page).to have_css("[data-testid='business-date-status']", text: "Open")
      end
      expect(page).to have_css("[data-testid='readiness-table']")
      expect(page).to have_no_css("[data-testid='blockers-table']")
      expect(page).to have_css("[data-testid='audit-history-table']")
      expect(page).to have_css("[data-testid='night-audit-index-tabs']")
      expect(page).to have_css("[data-testid='audit-history-panel']")
      expect(page).to have_css("[data-testid='index-advanced-actions-panel'][hidden]", visible: :all)
      expect(page).to have_link("Night Audit", href: hotel_night_audits_path(hotel))
      expect(page).to have_no_field("Business Date")
      expect(page).to have_content(business_date.strftime("%d %b %Y"))

      perform_enqueued_jobs do
        within("[data-testid='audit-action-form']") do
          fill_in "Notes", with: "Front desk close"
          click_button "Run Audit"
        end
      end

      expect(page).to have_content("Night audit has been scheduled in the background. Please wait while it processes.")
      expect(page).to have_content("Night Audit / #{business_date.strftime('%d %b %Y')}")
      expect(page).to have_content("Completed")
      expect(page).to have_content("Financial Summary")
      expect(page).to have_content("Summary")
      expect(page).to have_content("Audit Snapshot")
      expect(page).to have_css("[data-testid='night-audit-summary']")
      expect(page).to have_css("[data-testid='audit-details-card']")
      expect(page).to have_css("[data-testid='audit-snapshot-card']")
      expect(page).to have_css("[data-testid='payment-status-counts-card']")
      expect(page).to have_css("[data-testid='night-audit-show-tabs']")
      within("[data-testid='results-panel']") do
        expect(page).to have_content("Run Results")
        expect(page).to have_content("Hard Blockers")
        expect(page).to have_content("Warnings / Review Items")
      end
      expect(page).to have_css("[data-testid='financial-summary-panel'][hidden]", visible: :all)
      expect(page).to have_css("[data-testid='show-advanced-actions-panel'][hidden]", visible: :all)
      expect(page).to have_link("View Audit Packet")
    end

    it "shows blocker rows with links to affected bookings" do
      with_frozen_time Time.zone.local(2026, 5, 23, 10, 0, 0)
      business_date = Date.new(2026, 5, 22)
      BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)

      booking = create(:booking,
        hotel: hotel,
        status: "checked_in",
        payment_status: "captured",
        guest_name: "Aisha Tan",
        confirmation_token: "WS-BLOCK-LINK",
        check_in: business_date - 1.day,
        check_out: business_date,
        checked_in_at: 1.day.ago)

      visit hotel_night_audits_path(hotel)

      within("[data-testid='blockers-table']") do
        expect(page).to have_content("Due out not checked out")
        expect(page).to have_content("Aisha Tan")
        expect(page).to have_link("View Booking", href: hotel_booking_workspace_path(hotel, booking, tab: "folio_operations"))
      end
    end

    it "shows critical blockers on the result page" do
      with_frozen_time Time.zone.local(2026, 5, 23, 10, 0, 0)
      business_date = Date.new(2026, 5, 22)
      BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)

      create(:booking,
        hotel: hotel,
        status: "checked_in",
        payment_status: "captured",
        guest_name: "Aisha Tan",
        confirmation_token: "WS-BLOCK-001",
        check_in: business_date - 1.day,
        check_out: business_date + 1.day,
        checked_in_at: nil)

      visit hotel_night_audits_path(hotel)

      perform_enqueued_jobs do
        within("[data-testid='audit-action-form']") do
          click_button "Run Audit"
        end
      end

      expect(page).to have_content("Night audit has been scheduled in the background. Please wait while it processes.")
      expect(page).to have_content("Cannot close this date")
      expect(page).to have_content("Hard Blockers")
      expect(page).to have_content("Warnings / Review Items")
      expect(page).to have_content("Aisha Tan")
      expect(page).to have_content("Checked-in booking is missing check-in timestamp")
    end
  end

  context "with cuprite driver", js: true do
    before do
      driven_by(:cuprite)

      role.permissions << permission
      UserRole.create!(user: user, role: role)
      UserHotelAccess.create!(user: user, hotel: hotel, role: role)
      create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "no_show_auto_handling"), enabled: true)

      sign_in_through_ui(user)
    end

    it "navigates to the resolve page and displays blockers interactive wizard" do
      with_frozen_time Time.zone.local(2026, 5, 23, 10, 0, 0)
      business_date = Date.new(2026, 5, 22)
      BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)

      create(:booking,
        hotel: hotel,
        status: "checked_in",
        payment_status: "captured",
        guest_name: "Aisha Tan",
        confirmation_token: "WS-BLOCK-001",
        check_in: business_date - 1.day,
        check_out: business_date + 1.day,
        checked_in_at: nil)

      visit hotel_night_audits_path(hotel)

      within("[data-testid='audit-action-form']") do
        click_button "Run Audit"
      end

      expect(page).to have_content("Night Audit / #{business_date.strftime('%d %b %Y')}")

      perform_enqueued_jobs

      visit current_path

      expect(page).to have_text(/blocked/i)
      expect(page).to have_content("Resolve Blockers")
      click_link "Resolve Blockers"

      expect(page).to have_content("Resolve Audit Blockers")
      expect(page).to have_content("Missing Check-In Timestamps")
      expect(page).to have_content("Aisha Tan")
      click_button "Folios"
      expect(page).to have_content("Missing Folios")
      expect(page).to have_content("Recover Folio")
      expect(page).to have_link("View Booking")
      expect(page).to have_no_link("Go to Folio")

      visit hotel_night_audits_path(hotel)
      within("[data-testid='blockers-table']") do
        expect(page).to have_link("Resolve blockers")
      end
    end

    it "switches index and show tabs while preserving the active tab in the URL" do
      with_frozen_time Time.zone.local(2026, 5, 23, 10, 0, 0)
      business_date = Date.new(2026, 5, 22)
      BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)
      audit = create(:night_audit, hotel: hotel, business_date: business_date, status: "completed")

      visit hotel_night_audits_path(hotel)

      expect(page).to have_css("[data-testid='audit-history-panel']")
      expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Audit History")
      click_button "Advanced Actions"
      expect(page).to have_current_path(hotel_night_audits_path(hotel, tab: "advanced-actions"))
      expect(page).to have_css("[data-testid='index-advanced-actions-panel']")
      expect(page).to have_css("[data-testid='audit-history-panel']", visible: :hidden)
      expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Advanced Actions")
      refresh
      expect(page).to have_css("[data-testid='index-advanced-actions-panel']")
      expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Advanced Actions")

      visit hotel_night_audit_path(hotel, audit)

      expect(page).to have_css("[data-testid='results-panel']")
      expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Results")
      click_button "Financial Summary"
      expect(page).to have_current_path(hotel_night_audit_path(hotel, audit, tab: "financial-summary"))
      expect(page).to have_css("[data-testid='financial-summary-panel']")
      expect(page).to have_css("[data-testid='results-panel']", visible: :hidden)
      expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Financial Summary")

      click_button "Advanced Actions"
      expect(page).to have_current_path(hotel_night_audit_path(hotel, audit, tab: "advanced-actions"))
      expect(page).to have_css("[data-testid='show-advanced-actions-panel']")
      expect(page).to have_css("[data-testid='manual-adjustments']")
      expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Advanced Actions")
      refresh
      expect(page).to have_css("[data-testid='show-advanced-actions-panel']")
      expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Advanced Actions")
    end
  end
end
