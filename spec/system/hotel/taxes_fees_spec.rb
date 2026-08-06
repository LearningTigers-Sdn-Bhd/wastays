require "rails_helper"

RSpec.describe "Hotel taxes and fees", type: :system, js: true do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "live", sst_enabled: true, tourism_tax_enabled: true, tourism_tax_amount: 10.0) }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }
  let!(:heritage_fee) { HotelTax.create!(hotel: hotel, name: "Heritage Fee", rate_type: "flat", amount: 2.0, enabled: false) }
  let!(:manage_profile_permission) do
    Permission.find_or_create_by!(slug: "manage_hotel_profile") { |permission| permission.name = "Manage Hotel Profile" }
  end
  let!(:view_payouts_permission) do
    Permission.find_or_create_by!(slug: "view_payouts") { |permission| permission.name = "View Payouts" }
  end

  before do
    driven_by(:cuprite)

    RolePermission.find_or_create_by!(role: role, permission: manage_profile_permission)
    RolePermission.find_or_create_by!(role: role, permission: view_payouts_permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_through_ui(user)
  end

  it "shows the consolidated registry and URL-synced reference tab inside settings" do
    visit hotel_taxes_fees_path(hotel)

    expect(page).to have_css("h1", text: "Taxes & Fees")
    expect(page).to have_no_css('[data-testid="settings-tabs"]')

    within("#hotel-settings-sidebar") do
      expect(page).to have_no_link("Back to previous page")
      expect(page).to have_css("button.panel-sidebar__group-trigger[aria-label='Commercial']", visible: :all)
      expect(page).to have_link("Taxes & Fees", href: hotel_taxes_fees_path(hotel), visible: :all)
      expect(page).to have_css("a.panel-sidebar__child[aria-current='page']", text: "Taxes & Fees", visible: :all)
      expect(page).to have_no_link("Payouts", href: payouts_hotel_reports_path(hotel))
      expect(page).to have_no_css("summary.sidebar-group-parent", text: "Rooms & Rates")
    end

    expect(page).to have_css("[data-testid='taxes-fees-content']")
    expect(page).to have_css(
      ".panel-table__wrapper.rounded-md.border > table.panel-table[data-testid='taxes-fees-registry'][data-striped='true']"
    )
    expect(page).to have_css("#tax-registry-row-sst", text: "Service Tax (SST)")
    expect(page).to have_css("#tax-registry-row-tourism_tax", text: "Tourism Tax (TTx)")
    expect(page).to have_css("tr", text: "Heritage Fee")
    expect(page).to have_link("Add Tax or Fee")
    expect(page).to have_no_text("Primary Tax Settings")
    expect(page).to have_no_text("Additional Taxes & Fees")

    click_button "Malaysia Hotel Tax Reference"
    expect(page).to have_current_path(hotel_taxes_fees_path(hotel, tab: "malaysia_reference"))
    expect(page).to have_css("[data-testid='malaysia-tax-reference']", text: "Content last updated: 12 July 2026")
  end

  it "manages system taxes in dedicated settings action sheets" do
    visit hotel_taxes_fees_path(hotel)

    within("#tax-registry-row-sst") do
      click_link "Manage"
    end
    expect(page).to have_css("turbo-frame#settings_action_sheet dialog#manage-sst-sheet", text: "Service Tax (SST)")
    expect(page).to have_text("The SST rate is system-defined")
    expect(page).to have_no_field("Charge Amount")
    find("dialog#manage-sst-sheet button[aria-label='Close']").click

    within("#tax-registry-row-tourism_tax") do
      click_link "Manage"
    end
    expect(page).to have_css("turbo-frame#settings_action_sheet dialog#manage-tourism-tax-sheet", text: "Tourism Tax (TTx)")
    expect(page).to have_field("Charge Amount", with: "10.0")
  end

  it "opens add and edit forms in the settings action sheet" do
    visit hotel_taxes_fees_path(hotel)

    click_link "Add Tax or Fee"
    expect(page).to have_css("turbo-frame#settings_action_sheet dialog#add-hotel-tax-sheet", text: "Add Tax or Fee")
    expect(page).to have_field("Name")
    expect(page).to have_field("Code")
    expect(page).to have_select("Type", with_options: [ "Tax", "Fee" ], visible: :all)
    expect(page).to have_select("Applies To", with_options: [ "All guests", "Foreign guests only" ], visible: :all)
    expect(page).to have_select("Charge Rule", with_options: [ "Percentage", "Fixed" ], visible: :all)
    expect(page).to have_css(".panel-control-group[data-grouped='true'] [data-tax-code-field-target~='prefix']", text: "TAX_")

    find("#hotel_tax_charge_type-trigger").click
    find("#hotel_tax_charge_type-listbox [role='option']", text: "Fee").click
    expect(page).to have_css(".panel-control-group[data-grouped='false'][hidden]", visible: :all)
    expect(page).to have_css(
      ".panel-form-field > input#hotel_tax_code.panel-input + .panel-control-group[hidden]",
      visible: :all
    )
    expect(page).to have_css("[data-tax-code-field-target~='prefix'][hidden]", visible: :all)
    expect(page).to have_text("Saved without a prefix")

    find("dialog#add-hotel-tax-sheet button[aria-label='Close']").click
    expect(page).to have_no_css("dialog#add-hotel-tax-sheet[open]")

    within("tr", text: "Heritage Fee") { click_link "Manage" }
    expect(page).to have_css("turbo-frame#settings_action_sheet dialog#manage-hotel-tax-sheet", text: "Manage Tax or Fee")
    expect(page).to have_field("Name", with: "Heritage Fee")
    expect(page).to have_field("Code", with: "HF")
    expect(page).to have_field("Charge Amount", with: "2.0")
  end

  it "confirms deactivation before updating registry status" do
    visit hotel_taxes_fees_path(hotel)

    within("#tax-registry-row-sst") do
      find("input[type='checkbox'][name='hotel[sst_enabled]']", visible: :all).click
    end

    expect(page).to have_css("[role='alertdialog']", text: "Deactivate Service Tax (SST)?")
    expect(page).to have_text("Already-posted transactions will remain unchanged")
    click_button "Confirm"

    expect(page).to have_text("Service Tax (SST) updated.")
    expect(page).to have_current_path(hotel_taxes_fees_path(hotel), ignore_query: true)
    expect(hotel.reload.sst_enabled?).to be(false)
  end

  it "renders the room revenue page with both tabs" do
    visit hotel_room_revenue_path(hotel)

    expect(page).to have_content("Room Revenue")
    expect(page).to have_css("[data-testid='room-revenue-tax-rules-panel']", visible: :all)
    expect(page).to have_content("Tax rules for room revenue")
    expect(page).to have_content("Posting preview")
    expect(page).to have_content("Heritage Fee")

    click_button "Reservation policies"
    expect(page).to have_current_path(hotel_room_revenue_path(hotel, tab: "reservation_policies"))
    expect(page).to have_css("[data-testid='reservation-policies-registry']", visible: :all)
    expect(page).to have_content("Late checkout")
    expect(page).to have_content("Cancellation")
  end

  it "redirects the retired transaction codes page" do
    visit "/hotel/#{hotel.to_param}/settings/finance/transaction-codes"

    expect(page).to have_current_path(hotel_room_revenue_path(hotel), ignore_query: true)
  end
end
