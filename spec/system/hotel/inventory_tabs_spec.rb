require "rails_helper"

RSpec.describe "Hotel inventory tabs", type: :system, js: true do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "approved", default_currency: "MYR") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }
  let!(:room_type) { create(:room_type, hotel: hotel, name: "Twin Room", quantity: 4) }

  before do
    driven_by(:cuprite)

    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)
  end

  it "synchronizes top-level tabs, nested subtabs, URLs, and breadcrumbs" do
    visit hotel_inventory_index_path(hotel, tab: "advanced", subtab: "overrides")

    expect(page).to have_css("[data-testid='inventory-advanced-panel']")
    expect(page).to have_css("[data-testid='inventory-calendar-panel']", visible: :hidden)
    expect(page).to have_css("[data-testid='inventory-overrides-panel']")
    expect(page).to have_css("[data-testid='inventory-pricing-panel']", visible: :hidden)
    expect(page).to have_css("#inventory-tabs-tab-advanced[aria-selected='true']")
    expect(page).to have_css("#inventory-subtabs-tab-overrides[aria-selected='true']")
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Advanced Pricing")
    expect(page).to have_css("[data-subtabs-breadcrumb-label]", text: "Availability Overrides")

    click_button "Pricing Rules"

    expect(page).to have_current_path(hotel_inventory_index_path(hotel, tab: "advanced", subtab: "pricing"))
    expect(page).to have_css("[data-testid='inventory-pricing-panel']")
    expect(page).to have_css("#inventory-subtabs-tab-pricing[aria-selected='true']")
    expect(page).to have_css("[data-subtabs-breadcrumb-label]", text: "Pricing Rules")

    click_button "Rates & Availability"

    expect(page).to have_current_path(hotel_inventory_index_path(hotel, tab: "calendar", subtab: "pricing"))
    expect(page).to have_css("[data-testid='inventory-calendar-panel']")
    expect(page).to have_css("#inventory-tabs-tab-calendar[aria-selected='true']")
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Rates & Availability")
    expect(page).to have_css("[data-subtabs-breadcrumb-segment]", visible: :hidden)

    click_button "Channels & OTAs"

    expect(page).to have_css("[data-testid='inventory-channels-panel']")
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Channels & OTAs")
    expect(page).to have_css("[data-subtabs-breadcrumb-label]", text: "Derived Pricing & Allocations")

    click_button "Availability Rules"

    expect(page).to have_current_path(hotel_inventory_index_path(hotel, tab: "channels", subtab: "availability_rules"))
    expect(page).to have_css("[data-subtabs-breadcrumb-label]", text: "Availability Rules")
  end

  it "falls back to the default tab and subtab for unknown parameters" do
    visit hotel_inventory_index_path(hotel, tab: "unknown", subtab: "unknown")

    expect(page).to have_css("[data-testid='inventory-calendar-panel']")
    expect(page).to have_css("[data-testid='inventory-pricing-panel']", visible: :hidden)
    expect(page).to have_css("#inventory-tabs-tab-calendar[aria-selected='true']")
    expect(page).to have_css("#inventory-subtabs-tab-pricing[aria-selected='true']", visible: :all)
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Rates & Availability")
    expect(page).to have_css("[data-subtabs-breadcrumb-label]", text: "Pricing Rules", visible: :all)
    expect(page).to have_css("[data-panels-ui--breadcrumb-target='subtabSegment'].hidden", visible: :all)
  end

  it "preserves tab and filter state across calendar Turbo navigation" do
    visit hotel_inventory_index_path(
      hotel,
      start_date: Date.current,
      view_currencies: [ "MYR" ],
      display_currency: "MYR",
      room_type_id: room_type.id,
      tab: "calendar",
      subtab: "overrides"
    )

    find("a[title='Next 14 days']").click

    uri = URI.parse(page.current_url)
    query = Rack::Utils.parse_nested_query(uri.query)
    expect(query).to include(
      "display_currency" => "MYR",
      "room_type_id" => room_type.id.to_s,
      "tab" => "calendar",
      "subtab" => "overrides"
    )
    expect(query["view_currencies"]).to eq([ "MYR" ])
    expect(page).to have_css("[data-testid='inventory-calendar-panel']")
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Rates & Availability")
  end

  it "toggles the derived-pricing value with the dedicated pricing mode controller" do
    hotel.update!(preferred_channel_manager: "channex")
    adapter = instance_double(
      ChannelManagers::ChannexAdapter,
      connected_channels: [ { "id" => "channel-1", "attributes" => { "title" => "Booking.com" } } ]
    )
    allow(ChannelManagers::SyncOrchestrator).to receive(:adapter_for).with(hotel).and_return(adapter)

    visit hotel_inventory_index_path(hotel, tab: "channels", subtab: "derived_settings")

    within("form[data-controller='pricing-mode']") do
      expect(page).to have_css("[data-pricing-mode-target='value'].hidden", visible: :all)
      find("label", text: "Multiplier (%)").click
      expect(page).to have_css("[data-pricing-mode-target='value']:not(.hidden)")
      find("label", text: "Same Price").click
      expect(page).to have_css("[data-pricing-mode-target='value'].hidden", visible: :all)
    end
  end
end
