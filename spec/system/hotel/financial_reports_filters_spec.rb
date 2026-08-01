# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Financial report period filters", type: :system, js: true, frozen_time: Time.zone.local(2026, 7, 22, 10) do
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, plan: plan) }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account, slug: "hotel_owner", name: "Hotel owner") }

  before do
    driven_by(:cuprite)

    permission = Permission.find_or_create_by!(slug: "view_reports") { |record| record.name = "View reports" }
    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    feature = create(:feature, feature_group: create(:feature_group), slug: "booking_source_analysis")
    create(:plan_feature, plan: plan, feature: feature, enabled: true)

    create(
      :booking,
      hotel: hotel,
      guest_name: "Today financial guest",
      total_amount: 100,
      margin_amount: 10,
      net_amount: 90,
      payment_status: "captured",
      created_at: Time.zone.local(2026, 7, 22, 9)
    )
    create(
      :booking,
      hotel: hotel,
      guest_name: "Last month financial guest",
      total_amount: 250,
      margin_amount: 25,
      net_amount: 225,
      payment_status: "captured",
      created_at: Time.zone.local(2026, 6, 15, 9)
    )

    sign_in_through_ui(user)
  end

  it "updates summary and breakdown captions with their filtered data without reloading the page" do
    visit hotel_reports_path(hotel)
    expect(find("turbo-frame#reports_content .panel-page-header__caption")).to have_text("Wednesday, 22 Jul 2026")
    expect(page).to have_text("MYR 100.00")
    page.execute_script("window.__financialReportDocumentMarker = 'same-document'")

    select_last_month

    expect(find("turbo-frame#reports_content .panel-page-header__caption")).to have_text("01 Jun 2026 - 30 Jun 2026")
    expect(page).to have_text("MYR 250.00")
    expect(page).to have_no_text("MYR 100.00")
    expect(page.evaluate_script("window.__financialReportDocumentMarker")).to eq("same-document")

    visit breakdown_hotel_reports_path(hotel)
    expect(find("turbo-frame#breakdown_results .panel-page-header__caption")).to have_text("Wednesday, 22 Jul 2026")
    expect(page).to have_text("Today financial guest")
    expect(page).to have_no_text("Last month financial guest")
    page.execute_script("window.__financialReportDocumentMarker = 'same-document'")

    select_last_month

    expect(find("turbo-frame#breakdown_results .panel-page-header__caption")).to have_text("01 Jun 2026 - 30 Jun 2026")
    expect(page).to have_text("Last month financial guest")
    expect(page).to have_no_text("Today financial guest")
    expect(page.evaluate_script("window.__financialReportDocumentMarker")).to eq("same-document")
  end

  def select_last_month
    find("#date_preset-trigger").click
    find("#date_preset-listbox [role='option']", text: "Last Month").click
  end
end
