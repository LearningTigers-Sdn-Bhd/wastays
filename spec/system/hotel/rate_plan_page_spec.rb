require "rails_helper"

RSpec.describe "Rate plan page", type: :system, js: true do
  let(:hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user, account: hotel.account, role: "admin") }
  let(:role) { create(:role, account: hotel.account, slug: "hotel_owner", name: "Hotel Owner") }
  let!(:villa) { seed_room_type("Villa", %w[V1]) }
  let!(:suite) { seed_room_type("Suite", %w[S1]) }
  let!(:full_board) do
    create(:rate_plan, :custom, hotel: hotel, name: "Full Board").tap do |plan|
      create(:room_type_rate_plan, rate_plan: plan, room_type: villa, pricing_value: 400)
    end
  end

  def seed_room_type(name, numbers)
    Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: name, room_number_mode: "custom", quantity: numbers.size, base_price: 250.0, max_adults: 2, room_numbers: numbers }
    )
  end

  before do
    driven_by(:cuprite)

    %w[manage_account manage_hotel_profile].each do |slug|
      permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.titleize }
      RolePermission.find_or_create_by!(role: role, permission: permission)
    end
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)
  end

  def open_plan(tab: nil)
    visit edit_hotel_rate_plan_path(hotel, full_board, room_type_id: villa.id, tab: tab)
    expect(page).to have_css("h1", text: "Full Board", wait: 10)
  end

  def open_tab(name) = find("[role='tab']", text: name).click
  def active_tab = find("[role='tab'][aria-selected='true']").text.squish
  def category_open?(room_type) = find("#room-inventory-#{room_type.id} button[aria-expanded]", match: :first)["aria-expanded"] == "true"
  def save = click_button("Save rate plan", match: :first)
  def discard_dialog = find("#rate-plan-editor-discard-alert", visible: :all)
  def example_table = all("tbody tr, tfoot tr").map { |row| row.all("th, td").map { |cell| cell.text.squish } }

  # Walks the guided "Add discount" wizard (item 10b): one question per step,
  # ending with a real row (same fields/validation as before) once confirmed.
  def add_discount_via_wizard(min_nights:, value:, type: nil, from_night: nil)
    click_button "Add discount"
    within("[data-stay-discount-wizard-target='card']") do
      find("[data-stay-discount-wizard-target='minNights']").fill_in(with: min_nights.to_s)
      click_button "Continue"

      if type == "amount"
        choose("A fixed amount off")
      else
        click_button "Continue"
      end

      find("[data-stay-discount-wizard-target='value']").fill_in(with: value.to_s)
      click_button "Continue"

      if from_night
        choose("Only from night")
        find("[data-stay-discount-wizard-target='fromNightValue']").fill_in(with: from_night.to_s)
      end
      click_button "Continue"

      click_button "Add this discount"
    end
  end

  # The inventory list is a Turbo frame; a link inside it that forgets to
  # target the whole page loads into the frame and shows "Content missing".
  it "opens the plan's page from Room Inventory's Edit rate and New rate" do
    visit hotel_room_types_path(hotel, open: villa.id)
    menu_trigger = find("button[aria-label='Actions for Full Board in Villa']")
    click_in_overlay(menu_trigger)
    click_in_overlay("Edit rate", selector: :link)

    expect(page).to have_css("h1", text: "Full Board", wait: 10)
    expect(page).to have_current_path(edit_hotel_rate_plan_path(hotel, full_board, room_type_id: villa.id))
    expect(page).not_to have_text("Content missing")

    visit hotel_room_types_path(hotel, open: villa.id)
    within("#room-inventory-#{villa.id}") { click_link "New rate" }

    expect(page).to have_css("h1", text: "New rate plan", wait: 10)
    expect(page).to have_current_path(new_hotel_rate_plan_path(hotel, room_type_id: villa.id))
  end

  it "keeps the tab in the URL and returns to it after saving" do
    open_plan
    expect(active_tab).to eq("Details")

    open_tab "Discounts"
    expect(page).to have_current_path(/tab=discounts/)
    add_discount_via_wizard(min_nights: 3, value: 15)
    save

    expect(page).to have_text("Rate plan 'Full Board' saved.", wait: 10)
    expect(active_tab).to eq("Discounts")
    expect(full_board.reload.rate_plan_stay_discounts.sole).to have_attributes(min_nights: 3, value: 15)
  end

  it "saves fields from several tabs in one go" do
    open_plan
    fill_in "Rate plan name", with: "Full Board Plus"
    open_tab "Corporate/TA Portal"
    check "Hide from the public booking site"
    save

    expect(page).to have_css("h1", text: "Full Board Plus", wait: 10)
    expect(full_board.reload).to have_attributes(name: "Full Board Plus", hidden_from_public: true)
  end

  it "brings a required field on another tab forward instead of failing silently" do
    open_plan
    fill_in "Rate plan name", with: ""
    open_tab "Pricing"
    save

    expect(active_tab).to eq("Details")
    expect(full_board.reload.name).to eq("Full Board")
  end

  it "asks before leaving with unsaved changes, and returns to its room category" do
    open_plan
    fill_in "Rate plan name", with: "Unsaved name"
    find("a[aria-label='Back to Room Inventory']").click

    expect(discard_dialog).to be_visible
    click_in_overlay("Keep editing", selector: :button)
    expect(page).to have_css("h1", text: "Full Board")
    expect(find_field("Rate plan name").value).to eq("Unsaved name")

    find("a[aria-label='Back to Room Inventory']").click
    click_in_overlay("Leave page", selector: :button)

    expect(page).to have_css("#room-inventory-accordion", wait: 10)
    expect(category_open?(villa)).to be(true)
    expect(category_open?(suite)).to be(false)
    expect(full_board.reload.name).to eq("Full Board")
  end

  it "switches room category without asking at a per-guest property" do
    # Sell mode is fixed at creation; the hidden child-fee fields this page
    # disables on load only render at a per-guest property.
    hotel.update_column(:sell_mode, "per_person")
    create(:room_type_rate_plan, rate_plan: full_board, room_type: suite, pricing_value: 300)
    open_plan(tab: "pricing")

    find(".panel-select-menu__trigger", text: "Villa").click
    find("[role='option']", text: "Suite", visible: true).click

    expect(page).to have_current_path(/room_type_id=#{suite.id}/, wait: 10)
    expect(discard_dialog).not_to be_visible
  end

  it "still asks before switching room category with unsaved changes at a per-guest property" do
    hotel.update_column(:sell_mode, "per_person")
    create(:room_type_rate_plan, rate_plan: full_board, room_type: suite, pricing_value: 300)
    open_plan
    fill_in "Rate plan name", with: "Unsaved name"
    open_tab "Pricing"

    find(".panel-select-menu__trigger", text: "Villa").click
    find("[role='option']", text: "Suite", visible: true).click

    expect(discard_dialog).to be_visible
  end

  it "leaves without asking when nothing changed" do
    open_plan
    open_tab "Pricing"
    find("a[aria-label='Back to Room Inventory']").click

    expect(page).to have_css("#room-inventory-accordion", wait: 10)
    expect(category_open?(villa)).to be(true)
  end

  it "shows a worked example inside the wizard as it is filled in, then keeps it on the saved row" do
    open_plan(tab: "discounts")
    click_button "Add discount"

    within("[data-stay-discount-wizard-target='card']") do
      expect(page).to have_text("Enter the nights and the discount to see an example.")

      find("[data-stay-discount-wizard-target='minNights']").fill_in(with: "3")
      click_button "Continue"
      click_button "Continue" # percentage is the default — no auto-advance without a change
      find("[data-stay-discount-wizard-target='value']").fill_in(with: "15")
      expect(page).to have_text("Example: a 3-night stay at MYR 400 a night")
      expect(page).to have_css("table")
      expect(example_table).to eq([
        [ "Night 1", "MYR 400", "MYR 340" ],
        [ "Night 2", "MYR 400", "MYR 340" ],
        [ "Night 3", "MYR 400", "MYR 340" ],
        [ "Total (3 nights)", "MYR 1,200", "MYR 1,020" ]
      ])
      expect(page).to have_text("Guest saves MYR 180")

      click_button "Continue"
      click_button "Continue"
      click_button "Add this discount"
    end

    within("[data-role='stay-discount-row']") do
      expect(page).to have_text("Example: a 3-night stay at MYR 400 a night")

      find("select[name$='[from_night]']").select("Night 2")
      expect(page).to have_text("Guest saves MYR 120")
      expect(example_table).to eq([
        [ "Night 1", "MYR 400", "MYR 400 (full price)" ],
        [ "Night 2", "MYR 400", "MYR 340" ],
        [ "Night 3", "MYR 400", "MYR 340" ],
        [ "Total (3 nights)", "MYR 1,200", "MYR 1,080" ]
      ])

      find("select[name$='[discount_type]']").select("Fixed amount per night")
      find("input[name$='[value]']").fill_in(with: "50")
      expect(page).to have_css("tbody tr", text: "Night 3")
      expect(page).to have_text("Guest saves MYR 100")
      expect(page).to have_css("[data-stay-discount-example-target='unit']", text: "MYR")
    end
  end

  it "groups a long stay's example into ranges instead of one row per night" do
    open_plan(tab: "discounts")
    click_button "Add discount"

    within("[data-stay-discount-wizard-target='card']") do
      find("[data-stay-discount-wizard-target='minNights']").fill_in(with: "3")
      click_button "Continue"
      click_button "Continue"
      find("[data-stay-discount-wizard-target='value']").fill_in(with: "15")
      find("[data-stay-discount-wizard-target='simulateNights']").fill_in(with: "10")
      click_button "Continue"
      choose("Only from night")
      find("[data-stay-discount-wizard-target='fromNightValue']").fill_in(with: "3")

      expect(page).to have_text("Example: a 10-night stay at MYR 400 a night")
      expect(example_table).to eq([
        [ "Nights 1–2", "MYR 400", "MYR 400 (full price)" ],
        [ "Nights 3–10", "MYR 400", "MYR 340" ],
        [ "Total (10 nights)", "MYR 4,000", "MYR 3,520" ]
      ])
    end
  end

  it "lets the Travel agents picker actually be used once revealed by Who can book it" do
    agency = create(:hotel_corporate_account, hotel: hotel)

    open_plan(tab: "availability")
    expect(active_tab).to eq("Corporate/TA Portal")

    panel = find("[data-value-reveal-target='panel']", visible: :all)
    expect(panel[:hidden]).to eq(true)

    # PanelsUI::SelectMenu, not the plain browser dropdown (item 11).
    find_by_id("rate_plan_ta_access-trigger").click
    find("#rate_plan_ta_access-listbox [role='option']", text: "All travel agents except…").click

    panel = find("[data-value-reveal-target='panel']")
    expect(panel[:hidden]).to eq(false)

    # Regression: the multi-select used to initialise disabled (its panel
    # starts hidden) and stay permanently unusable even once revealed.
    multi_select = panel.find("[data-controller~='panels-ui--multi-select']")
    multi_select.find(".ts-control").click
    expect(multi_select).to have_css(".ts-wrapper.dropdown-active")
    multi_select.find(".ts-dropdown .option", text: agency.corporate_account.name).click

    expect(page).to have_css(".ts-control .item", text: agency.corporate_account.name)
  end

  it "keeps the page responsive when Who can book it hides the Travel agents picker again" do
    open_plan(tab: "availability")

    find_by_id("rate_plan_ta_access-trigger").click
    find("#rate_plan_ta_access-listbox [role='option']", text: "All travel agents except…").click
    find_by_id("rate_plan_ta_access-trigger").click
    find("#rate_plan_ta_access-listbox [role='option']", text: "Hidden from travel agents").click

    # The picker's disabled-state observer used to re-trigger itself forever here.
    expect(page.evaluate_script("1 + 1")).to eq(2)
    expect(find("[data-value-reveal-target='panel']", visible: :all)[:hidden]).to eq(true)
  end

  it "walks the pricing wizard one question at a time instead of showing every field" do
    open_plan(tab: "pricing")

    expect(page).to have_field("Relationship to Standard Rate", visible: :all) # rendered, but its step is hidden
    expect(page).to have_no_field("Adjustment", visible: :visible)

    expect(page).to have_css("[aria-current='step']", text: "Pricing method")

    choose "Adjust Standard Rate"
    expect(page).to have_field("Relationship to Standard Rate", visible: :visible)
    expect(page).to have_no_field("Adjustment", visible: :visible)
    expect(page).to have_css("[aria-current='step']", text: "Direction")
    expect(page).to have_button("Adjust Standard Rate") # step 1 in the progress list, named after the choice

    click_button "Continue"
    expect(page).to have_field("Adjustment", visible: :visible)
    expect(page).to have_no_button("Continue")
    expect(page).to have_text("All set — save the rate plan below")

    fill_in "Adjustment", with: "-20"
    expect(page).to have_text("MYR 200.00 per night") # 250 standard rate, -20%
  end

  it "creates a plan from Room Inventory's New rate and lands on its page" do
    visit new_hotel_rate_plan_path(hotel, room_type_id: suite.id)
    expect(page).to have_css("h1", text: "New rate plan", wait: 10)

    fill_in "Rate plan name", with: "Half Board"
    open_tab "Pricing"
    choose "Set prices directly" # already the default — picking it again still moves on
    fill_in "Nightly room price", with: "300"
    click_button "Create rate plan", match: :first

    expect(page).to have_text("Rate plan 'Half Board' created.", wait: 10)
    plan = hotel.rate_plans.find_by!(name: "Half Board")
    expect(page).to have_current_path(edit_hotel_rate_plan_path(hotel, plan, room_type_id: suite.id, tab: "pricing"))
    expect(plan.room_type_rate_plans.sole).to have_attributes(room_type_id: suite.id, pricing_value: 300)
  end
end
