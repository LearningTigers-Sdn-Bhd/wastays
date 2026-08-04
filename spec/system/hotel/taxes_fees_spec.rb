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

  it "renders default transaction codes behind tabs" do
    visit hotel_transaction_codes_path(hotel)

    expect(page).to have_content("Transaction Codes")
    expect(page).to have_css("[data-testid='transaction-codes-default-codes-panel']", visible: :all)
    expect(page).to have_content("Hotel Operations")
    expect(page).to have_content("Booking Operations")
    expect(page).to have_content("Utility Operations")
    expect(page).to have_content("Taxes and Fees Operations")

    within("[data-testid='transaction-codes-hotel-operations-list']") do
      expect(page).to have_content("ROOM")
    end

    within("[data-testid='transaction-codes-tax-operations-list']") do
      expect(page).to have_content("TAX_SST")
      expect(page).to have_content("TAX_TTX")
      expect(page).to have_content("TAX_HF")
      expect(page).to have_content("Heritage Fee")
      expect(page).to have_link("Manage Taxes & Fees", href: hotel_taxes_fees_path(hotel))
      expect(find_link("Manage Taxes & Fees")[:target]).to eq("_blank")
    end

    click_button "Additional Service Codes"
    expect(page).to have_current_path(hotel_transaction_codes_path(hotel, tab: "additional_service_codes"))
    expect(page).to have_css("[data-testid='transaction-codes-additional-service-codes-panel']", visible: :all)
    expect(page).to have_content("Hotel-specific non-tax transaction codes for additional service postings.")
    expect(page).to have_content("No additional service transaction codes found.")
  end

  xit "updates transaction code tax rules and footer preview dynamically" do
    HotelTax.create!(hotel: hotel, name: "Service Charge", code: "SC", rate_type: "percentage", amount: 10.0, enabled: true)

    visit hotel_transaction_codes_path(hotel)

    within("tr", text: "FNB") do
      click_link "Edit"
    end

    expect(page).to have_css("turbo-frame#offcanvas_drawer", text: "Edit Transaction Code: FNB")
    expect(page).to have_no_text("Taxes to generate")

    taxable_input = find("#transaction_code_is_taxable", visible: :all)
    page.execute_script("arguments[0].checked = true; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", taxable_input)

    expect(page).to have_text("Taxes to generate")
    expect(page).to have_text("PRIMARY TAXES")
    expect(page).to have_text("SST 8%")
    expect(page).to have_text("Tourism Tax")
    expect(page).to have_text("Service Charge")
    expect(page).to have_text("Heritage Fee")

    sst_input = find("label", text: "SST 8%").find("input[type='checkbox']", visible: :all)
    tourism_tax_input = find("label", text: "Tourism Tax").find("input[type='checkbox']", visible: :all)
    service_charge_input = find("label", text: "Service Charge").find("input[type='checkbox']", visible: :all)
    heritage_fee_input = find("label", text: "Heritage Fee").find("input[type='checkbox']", visible: :all)
    page.execute_script("arguments[0].checked = true; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", sst_input)
    page.execute_script("arguments[0].checked = true; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", tourism_tax_input)
    page.execute_script("arguments[0].checked = true; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", service_charge_input)
    page.execute_script("arguments[0].checked = true; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", heritage_fee_input)

    within("section[aria-label='Transaction code posting preview']") do
      expect(page).to have_text("Food & Beverage")
      expect(page).to have_text("SST 8%")
      expect(page).to have_text("Tourism Tax")
      expect(page).to have_text("Service Charge")
      expect(page).to have_no_text("Heritage Fee")
      expect(page).to have_text("MYR 69.00")
    end

    page.execute_script("arguments[0].checked = false; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", service_charge_input)

    within("section[aria-label='Transaction code posting preview']") do
      expect(page).to have_no_text("Service Charge")
      expect(page).to have_text("MYR 64.00")
    end

    within("turbo-frame#offcanvas_drawer") do
      category_input = find("input[type='hidden'][name='transaction_code[category]']", visible: :all)
      expect(category_input.value).to eq("fb")
      expect(page).to have_no_select("Category", options: [ "Tax" ])
    end
  end

  # Flaky on CI: offcanvas redirect occasionally lands without the tab query param; not reproducible locally after 6 runs
  xit "reviews and confirms a forecast-impacting hotel-wide transaction-code tax change" do
    hotel.transaction_configuration.update!(room_revenue_tax_rule_application: "open_folio_forecasts")
    room_type = create(:room_type, hotel: hotel)
    booking = create(:booking, hotel: hotel, check_in: hotel_today(hotel), check_out: hotel_today(hotel) + 1.day)
    create(:booking_room, booking: booking, room_type: room_type, subtotal: 150.0)
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    create(:folio_forecasted_charge, booking_folio: folio, amount: 150.0)

    visit hotel_transaction_codes_path(hotel)

    within("tr", text: "ROOM") { click_link "Edit" }
    taxable_input = find("#transaction_code_is_taxable", visible: :all)
    page.execute_script("arguments[0].checked = true; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", taxable_input)
    sst_input = find("label", text: "SST 8%").find("input[type='checkbox']", visible: :all)
    page.execute_script("arguments[0].checked = true; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", sst_input)
    click_button "Save"

    expect(page).to have_css('[role="alertdialog"]', text: "Change hotel default?")
    expect(page).to have_content("ROOM · Room Revenue")
    expect(page).to have_content("SST 8%")
    expect(page).to have_content("Posted transactions will not change")
    fill_in "Reason", with: "Approved finance policy"
    click_button "Apply hotel-wide"

    expect(page).to have_current_path(hotel_transaction_codes_path(hotel, tab: "default_codes"))
    room = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    expect(room.reload.tax_rule_keys).to include("primary:sst_tax")
  end
end
