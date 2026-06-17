require "rails_helper"

RSpec.describe "Hotel taxes and fees", type: :system, js: true do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "live", tourism_tax_enabled: true, tourism_tax_amount: 10.0) }
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

    visit login_path
    fill_in "Email Address", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In to Portal"
  end

  it "shows finance pages in the finance sidebar section" do
    visit hotel_taxes_fees_path(hotel)

    finance_section = page.all(".sidebar-nav-group", text: "Finance", visible: :all).first
    finance_links = finance_section.all("a", visible: :all).map(&:text)
    expect(finance_links).to include("Taxes & Fees", "Transaction Codes", "Payouts")
    expect(finance_links.index("Taxes & Fees")).to be < finance_links.index("Transaction Codes")
    expect(finance_links.index("Transaction Codes")).to be < finance_links.index("Payouts")
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

  it "opens add and edit fee forms in the fullscreen offcanvas" do
    visit hotel_taxes_fees_path(hotel)

    within("[data-testid='additional-taxes-fees']") do
      click_link "Add Fee"
    end

    expect(page).to have_css("turbo-frame#offcanvas_drawer", text: "Add Fee")
    expect(page).to have_field("Name")
    expect(page).to have_field("Tax Code")
    expect(page).to have_select("Type", options: [ "Fixed RM", "Percentage" ])
    expect(page).to have_css("label", text: "Enabled")
    expect(page).to have_css("label", text: "Foreign guests only")

    click_button "Cancel"

    within("[data-testid='additional-taxes-fees']", text: "Heritage Fee") do
      click_link "Edit", match: :first
    end

    expect(page).to have_css("turbo-frame#offcanvas_drawer", text: "Edit Fee")
    expect(page).to have_field("Name", with: "Heritage Fee")
    expect(page).to have_field("Tax Code", with: "HF")
    expect(page).to have_field("Amount", with: "2.0")
  end

  it "renders default transaction codes behind tabs" do
    visit hotel_transaction_codes_path(hotel)

    expect(page).to have_content("Transaction Codes")
    expect(page).to have_css("[data-testid='transaction-codes-default-codes-panel']", visible: :all)
    expect(page).to have_content("System-required and tax-related transaction codes used by folio posting and accounting exports.")
    expect(page).to have_content("ROOM")
    expect(page).to have_content("TAX_SST")
    expect(page).to have_content("TAX_TTX")
    expect(page).to have_content("TAX_HF")
    expect(page).to have_content("Heritage Fee")

    click_button "Additional Service Codes"
    expect(page).to have_current_path(hotel_transaction_codes_path(hotel, tab: "additional_service_codes"))
    expect(page).to have_css("[data-testid='transaction-codes-additional-service-codes-panel']", visible: :all)
    expect(page).to have_content("Hotel-specific non-tax transaction codes for additional service postings.")
    expect(page).to have_content("No additional service transaction codes found.")
  end
end
