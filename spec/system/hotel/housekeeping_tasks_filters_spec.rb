# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Housekeeping task filters", type: :system do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, account:, status: "live", plan:) }
  let(:user) { create(:user, account:, role: "admin") }
  let(:role) { create(:role, account:, slug: "front_desk", name: "Front Desk") }
  let!(:room_type) do
    create(:room_type, hotel:, room_number_mode: "custom", quantity: 2, room_numbers: %w[101 202])
  end

  before do
    permission = Permission.find_or_create_by!(slug: "dispatch_housekeeping_tasks") do |record|
      record.name = "Dispatch housekeeping tasks"
    end
    RolePermission.find_or_create_by!(role:, permission:)
    UserRole.find_or_create_by!(user:, role:)
    UserHotelAccess.find_or_create_by!(user:, hotel:, role:)

    feature_group = create(:feature_group)
    create(
      :plan_feature,
      plan:,
      feature: create(:feature, feature_group:, slug: "task_assignment_minibar_log"),
      enabled: true
    )
    create(:room_status, hotel:, room_type:, room_number: "101", status: "dirty")
    create(:room_status, hotel:, room_type:, room_number: "202", status: "ready")

    sign_in_as_system(user)
  end

  it "updates filters and sorting inside the table frame" do
    visit hotel_housekeeping_tasks_path(hotel)
    page.execute_script("document.querySelector('h1').dataset.pageMarker = 'preserved'")

    find("#hk-room-status-filter-trigger").click
    find("[role='menuitemcheckbox']", text: "All room statuses").click

    expect(page).to have_text("No rooms found")
    expect(page).to have_css("#hk-room-status-filter-menu:popover-open")
    expect(all("#hk-room-status-filter-menu [role='menuitemcheckbox']").map { |item| item["aria-checked"] }).to all(eq("false"))

    find("[role='menuitemcheckbox']", text: "All room statuses").click
    expect(page).to have_css("#hk-room-#{room_type.id}-101")
    expect(all("#hk-room-status-filter-menu [role='menuitemcheckbox']").map { |item| item["aria-checked"] }).to all(eq("true"))

    find("[role='menuitemcheckbox']", text: "Dirty").click

    expect(page).to have_no_css("#hk-room-#{room_type.id}-101")
    expect(page).to have_css("#hk-room-#{room_type.id}-202")
    expect(page).to have_css("h1[data-page-marker='preserved']")
    expect(page).to have_css("#hk-room-status-filter-menu:popover-open")
    page_filters = Rack::Utils.parse_nested_query(URI.parse(page.current_url).query)
    export_filters = Rack::Utils.parse_nested_query(URI.parse(find("#export-csv-link", visible: :all)[:href]).query)
    expect(page_filters.fetch("room_statuses")).to include("ready")
    expect(export_filters.fetch("room_statuses")).to match_array(page_filters.fetch("room_statuses"))
    expect(page_filters.fetch("room_statuses")).not_to include("dirty")

    find("#hk-room-status-filter-trigger").click
    click_link "Arrival"

    expect(page).to have_css('th[aria-sort="ascending"]')
    expect(page).to have_css("h1[data-page-marker='preserved']")
    page_filters = Rack::Utils.parse_nested_query(URI.parse(page.current_url).query)
    export_filters = Rack::Utils.parse_nested_query(URI.parse(find("#export-csv-link", visible: :all)[:href]).query)
    expect(page_filters).to include("sort" => "arrival", "direction" => "asc")
    expect(export_filters).to include("sort" => "arrival", "direction" => "asc")
    expect(export_filters.fetch("room_statuses")).to match_array(page_filters.fetch("room_statuses"))
  end

  it "persists visible columns and clears selected rooms when the table changes" do
    visit hotel_housekeeping_tasks_path(hotel)

    check "Select #{room_type.name} 101"
    expect(page).to have_button("Export 1")

    click_button "Columns"
    find("[role='menuitemcheckbox']", text: "Pax").click

    expect(page).to have_no_css('th[data-column-key="pax"]')
    expect(page).to have_button("Export")

    refresh
    expect(page).to have_no_css('th[data-column-key="pax"]')
    expect(ReportViewPreference.find_by!(hotel:, user:, report_key: "housekeeping_tasks").visible_columns).not_to include("pax")
  end
end
