# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Run Night Audit sheet", type: :system, js: true do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:business_date) { Date.new(2026, 7, 29) }
  let(:hotel) { create(:hotel, :without_current_business_date, account:, plan:, status: "live", time_zone: "Kuala Lumpur") }
  let(:user) { create(:user, account:, role: "hotel_staff") }
  let(:role) { create(:role, account:, slug: "night_auditor", name: "Night Auditor") }

  before do
    driven_by(:cuprite)
    role.permissions << permission("manage_night_audit", "Manage Night Audit")
    role.permissions << permission("manage_bookings", "Manage Bookings")
    role.permissions << permission("view_bookings", "View Bookings")
    create(:user_hotel_access, user:, hotel:, role:)
    create(:plan_feature, plan:, feature: create(:feature, feature_group:, slug: "no_show_auto_handling"), enabled: true)
    BusinessDates::ResetAuthority.call!(hotel:, date: business_date)
    sign_in_through_ui(user)
  end

  it "continues from confirmation, completes a secondary booking action, and reaches Confirm" do
    booking = create(:booking,
      hotel:, status: "confirmed", check_in: business_date, check_out: business_date + 1.day,
      confirmation_token: "WS-SYSTEM-1")
    create(:booking_folio, hotel:, booking:)

    page.current_window.resize_to(390, 844)
    visit hotel_front_desk_path(hotel)
    original_path = page.current_path
    find("button[command='show-modal'][commandfor='hotel-sidebar-mobile']").click
    within("dialog#hotel-sidebar-mobile[open]") { click_link "Run Night Audit" }

    expect(page).to have_css("dialog#confirm-run-night-audit-sheet[open]")
    expect(page).to have_content("Night Audit checks bookings, payments, and room charges")
    expect(page).to have_button("Continue")
    expect(page).to have_no_content("Payments & charges")
    expect(page).to have_current_path(original_path)

    within("dialog#confirm-run-night-audit-sheet") { click_in_overlay "Continue" }

    expect(page).to have_css("dialog#run-night-audit-sheet[open] [aria-current='step']", text: "Bookings")
    expect(booking.reload.status).to eq("no_show_detected")

    within("dialog#run-night-audit-sheet") { click_in_overlay "Choose an action" }
    click_in_overlay "Mark as no-show"

    expect(page).to have_css("dialog#booking-no-show-sheet[open]")
    within("dialog#booking-no-show-sheet") do
      fill_in "No-show reason", with: "Guest did not arrive"
      click_in_overlay "Confirm no-show"
    end

    expect(page).to have_no_css("dialog#booking-no-show-sheet[open]")
    expect(page).to have_css("dialog#run-night-audit-sheet[open] [aria-current='step']", text: "Confirm")
    expect(page).to have_content("Ready to run")
    expect(booking.reload.status).to eq("no_show")

    within("dialog#run-night-audit-sheet") do
      fill_in "Notes", with: "Handled by night team"
      click_in_overlay "Run Night Audit"
    end

    expect(page).to have_content("Night Audit is running")
    expect(page).to have_css("dialog#run-night-audit-sheet[open] [role='progressbar']", count: 1)
    expect(page).to have_no_css("dialog#run-night-audit-sheet[open] .panel-spinner")
    expect(hotel.night_audits.find_by!(business_date:).notes).to eq("Handled by night team")
    expect(page).to have_current_path(original_path)
  end

  private

  def permission(slug, name)
    Permission.find_or_create_by!(slug:) { |record| record.name = name }
  end
end
