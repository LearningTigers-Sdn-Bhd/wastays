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
    click_button "Add discount"
    within("[data-role='stay-discount-row']") do
      find("input[name$='[min_nights]']").fill_in(with: "3")
      find("input[name$='[value]']").fill_in(with: "15")
    end
    save

    expect(page).to have_text("Rate plan 'Full Board' saved.", wait: 10)
    expect(active_tab).to eq("Discounts")
    expect(full_board.reload.rate_plan_stay_discounts.sole).to have_attributes(min_nights: 3, value: 15)
  end

  it "saves fields from several tabs in one go" do
    open_plan
    fill_in "Rate plan name", with: "Full Board Plus"
    open_tab "Availability"
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
    click_in_overlay("Discard changes", selector: :button)

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

  it "shows a worked example for a long-stay discount as it is filled in" do
    open_plan(tab: "discounts")
    click_button "Add discount"

    within("[data-role='stay-discount-row']") do
      expect(page).to have_text("Enter the nights and the discount to see an example.")

      find("input[name$='[min_nights]']").fill_in(with: "3")
      find("input[name$='[value]']").fill_in(with: "15")
      expect(page).to have_text("Example: a 3-night stay at MYR 400 a night")
      expect(page).to have_text("Nights 1–3: MYR 400 → MYR 340")
      expect(page).to have_text("Total: MYR 1,200 → MYR 1,020 (guest saves MYR 180)")

      find("select[name$='[from_night]']").select("Night 2")
      expect(page).to have_text("Night 1: MYR 400 (normal price)")
      expect(page).to have_text("Total: MYR 1,200 → MYR 1,080 (guest saves MYR 120)")

      find("select[name$='[discount_type]']").select("Fixed amount per night")
      find("input[name$='[value]']").fill_in(with: "50")
      expect(page).to have_text("Nights 2–3: MYR 400 → MYR 350")
      expect(page).to have_css("[data-stay-discount-example-target='unit']", text: "MYR")
    end
  end

  it "creates a plan from Room Inventory's New rate and lands on its page" do
    visit new_hotel_rate_plan_path(hotel, room_type_id: suite.id)
    expect(page).to have_css("h1", text: "New rate plan", wait: 10)

    fill_in "Rate plan name", with: "Half Board"
    open_tab "Pricing"
    fill_in "Nightly room price", with: "300"
    click_button "Create rate plan", match: :first

    expect(page).to have_text("Rate plan 'Half Board' created.", wait: 10)
    plan = hotel.rate_plans.find_by!(name: "Half Board")
    expect(page).to have_current_path(edit_hotel_rate_plan_path(hotel, plan, room_type_id: suite.id, tab: "pricing"))
    expect(plan.room_type_rate_plans.sole).to have_attributes(room_type_id: suite.id, pricing_value: 300)
  end
end
