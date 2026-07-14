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

  it "shows taxes and fees inside settings navigation mode" do
    visit hotel_taxes_fees_path(hotel)

    expect(page).to have_css("h1", text: "Taxes & Fees")
    within('[data-testid="settings-tabs"]') do
      expect(page).to have_link('Taxes & Fees')
    end

    within("#hotel-sidebar") do
      expect(page).to have_link("Back to previous page")
      expect(page).to have_link("Finance", href: hotel_taxes_fees_path(hotel))
      expect(page).to have_css("a.sidebar-nav-link-active", text: "Finance")
      expect(page).to have_no_link("Payouts", href: payouts_hotel_reports_path(hotel))
      expect(page).to have_no_css("summary.sidebar-group-parent", text: "Rooms & Rates")
    end

    expect(page).to have_css("[data-testid='taxes-fees-content']")
    expect(page).to have_css("[data-testid='primary-tax-settings']", text: "Tourism Tax")
    expect(page).to have_css("[data-testid='additional-taxes-fees']", text: "Heritage Fee")
    expect(page).to have_css("[data-testid='malaysia-tax-reference']", text: "Malaysia Hotel Tax Reference Table")
    expect(page).to have_css("input[name='hotel[tourism_tax_enabled]']", visible: :all)
    expect(page).to have_css("input[name='hotel[sst_enabled]']", visible: :all)
    expect(page).to have_no_button("ON")
    expect(page).to have_no_button("OFF")
    expect(page).to have_no_css("[data-testid='taxes-transactions-tabs']")
    expect(page).to have_no_button("Default Transaction Code")
  end

  it "shows inline tourism tax editing controls" do
    visit hotel_taxes_fees_path(hotel)

    within("[data-testid='primary-tax-settings']") do
      click_link "Edit", match: :first
      expect(page).to have_field("hotel_tourism_tax_amount", with: "10.0")
      expect(page).to have_button("Save")
      expect(page).to have_link("Cancel")
    end
  end

  xit "opens add and edit fee forms in the fullscreen offcanvas" do
    visit hotel_taxes_fees_path(hotel)

    within("[data-testid='additional-taxes-fees']") do
      click_link "Add Fee"
    end

    expect(page).to have_css("turbo-frame#offcanvas_drawer", text: "Add Fee")
    expect(page).to have_field("Name")
    expect(page).to have_field("Transaction Code")
    expect(page).to have_select("Charge Type", options: [ "Tax", "Charge", "Others" ])
    expect(page).to have_select("Amount Type", options: [ "Fixed RM", "Percentage" ])
    expect(page).to have_css("label", text: "Enabled")
    expect(page).to have_css("label", text: "Foreign guests only")
    expect(page).to have_css("span", text: "TAX_")

    select "Charge", from: "Charge Type"
    expect(page).to have_no_css("span", text: "TAX_", visible: :visible)

    click_button "Cancel"

    within("[data-testid='additional-taxes-fees']", text: "Heritage Fee") do
      click_link "Edit", match: :first
    end

    expect(page).to have_css("turbo-frame#offcanvas_drawer", text: "Edit Fee")
    expect(page).to have_field("Name", with: "Heritage Fee")
    expect(page).to have_field("Transaction Code", with: "HF")
    expect(page).to have_field("Amount", with: "2.0")
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
    booking = create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 1.day)
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
