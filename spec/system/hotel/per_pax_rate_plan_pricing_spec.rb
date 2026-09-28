# frozen_string_literal: true

require "rails_helper"

# Test plan phase M: configure a per-person plan through the rate plan page.
# docs/wastays/per-pax-ta-reservations-test-plan-2026-09-25.md §7.1.
# M10 (age bands) and M11 (long-stay wizard) are pricing-mode-agnostic and
# already covered by spec/system/hotel/rate_plan_age_bands_spec.rb and
# rate_plan_page_spec.rb's discount-wizard tests, cited rather than duplicated.
# M12/M13/M14 ("Who can book it", its validation, and switching category not
# prompting at a per-guest property) are likewise already covered generically
# by rate_plan_page_spec.rb. This file covers what's specific to per-person
# Manual/Derived/Auto pricing: M1-M4, M6-M9.
RSpec.describe "Per-pax rate plan pricing page", type: :system, js: true do
  let(:hotel) { create(:hotel, :per_person, status: "live") }
  let(:user) { create(:user, account: hotel.account, role: "admin") }
  let(:role) { create(:role, account: hotel.account, slug: "hotel_owner", name: "Hotel Owner") }
  let!(:suite) do
    Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "Pax Suite", room_number_mode: "custom", quantity: 2, base_price: 150.0,
                    max_adults: 4, room_numbers: %w[F1 F2] }
    )
  end
  let(:std_plan) { suite.standard_rate_plan }

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

  def open_pricing(plan)
    visit edit_hotel_rate_plan_path(hotel, plan, room_type_id: suite.id, tab: "pricing")
    expect(page).to have_css("h1", text: plan.name, wait: 10)
  end

  def save = click_button("Save rate plan", match: :first)

  # M1: Manual - type 4 prices, save, confirm they persist exactly.
  it "M1: saves Manual prices for each adult count" do
    open_pricing(std_plan)

    choose "Set prices directly"
    fill_in "1 adult", with: "250"
    fill_in "2 adults", with: "440"
    fill_in "3 adults", with: "600"
    fill_in "4 adults", with: "740"
    save

    expect(page).to have_css("h1", wait: 10)
    expect(page).not_to have_text(/error|problem/i)
    assignment = std_plan.room_type_rate_plans.find_by!(room_type: suite)
    prices = assignment.occupancy_prices.index_by(&:adults).transform_values { |row| row.price.to_d }
    expect(prices).to eq({ 1 => 250.to_d, 2 => 440.to_d, 3 => 600.to_d, 4 => 740.to_d })
  end

  # M2: Manual with one count blank -> refused, nothing saved
  it "M2: refuses to save when one adult count is left blank" do
    open_pricing(std_plan)

    choose "Set prices directly"
    fill_in "1 adult", with: "250"
    fill_in "2 adults", with: "440"
    fill_in "3 adults", with: "600"
    fill_in "4 adults", with: ""
    save

    expect(page).to have_text(/price/i, wait: 10) # an error mentioning the missing price
    expect(std_plan.room_type_rate_plans.find_by(room_type: suite)&.occupancy_prices).to be_blank
  end

  # M3: Derived -10% of Standard
  it "M3: Derived -10% of Standard prices every adult count from Standard's" do
    save_manual_std!

    fb = create(:rate_plan, :custom, hotel: hotel, name: "Full Board", ta_access: "hidden", room_type: suite)
    open_pricing(fb)

    choose "Adjust Standard Rate"
    click_button "Continue"
    fill_in "Adjustment", with: "-10"
    save

    expect(page).to have_css("h1", wait: 10)
    expect(page).not_to have_text(/error|problem/i)
    assignment = fb.room_type_rate_plans.find_by!(room_type: suite)
    expect(assignment).to have_attributes(pricing_mode: "multiplier", pricing_value: -10.to_d)
    prices = (1..4).index_with do |adults|
      Rates::ResolveEffectiveNightlyPrice.call(room_type: suite.reload, rate_plan: fb, date: Date.current + 5, adults: adults).amount
    end
    expect(prices).to eq({ 1 => 225.to_d, 2 => 396.to_d, 3 => 540.to_d, 4 => 666.to_d })
  end

  # M4: reopening a Derived per-person plan shows Derived, with its rule.
  it "M4: reopening a Derived plan shows it as Derived, with the -10% kept" do
    save_manual_std!
    fb = create(:rate_plan, :custom, hotel: hotel, name: "Full Board", ta_access: "hidden", room_type: suite)
    save_derived!(fb, -10)

    open_pricing(fb)

    expect(page).to have_checked_field("Adjust Standard Rate")
    click_button "Continue"
    click_button "Continue"
    expect(page).to have_field("Adjustment", with: "-10.0")
  end

  # M6: Derived when Standard's own list is incomplete
  it "M6: Derived is refused when Standard's occupancy matrix is incomplete" do
    # Standard has no prices at all yet (save_manual_std! not called).
    fb = create(:rate_plan, :custom, hotel: hotel, name: "Full Board", ta_access: "hidden", room_type: suite)
    open_pricing(fb)

    choose "Adjust Standard Rate"
    click_button "Continue"
    fill_in "Adjustment", with: "-10"
    save

    expect(page).to have_text(/standard rate occupancy matrix/i, wait: 10)
    expect(fb.room_type_rate_plans.find_by(room_type: suite)&.occupancy_prices).to be_blank
  end

  # M7: Auto - anchor 480 @ 2 adults, +150 amount / extra, -30% / fewer
  it "M7: Auto builds the full ladder from an anchor and two steps" do
    prm = create(:rate_plan, :custom, hotel: hotel, name: "Promo", ta_access: "hidden", room_type: suite)
    open_pricing(prm)

    choose "Generate from a starting rate"
    fill_in "Primary occupancy", with: "2"
    click_button "Continue"
    fill_in "Rate at primary occupancy", with: "480"
    click_button "Continue"
    fill_in "Increase by", with: "150"
    select "MYR", from: "Increase unit"
    click_button "Continue"
    fill_in "Decrease by", with: "30"
    select "%", from: "Decrease unit"
    save

    expect(page).to have_css("h1", wait: 10)
    expect(page).not_to have_text(/error|problem/i)
    assignment = prm.room_type_rate_plans.find_by!(room_type: suite)
    prices = assignment.occupancy_prices.index_by(&:adults).transform_values { |row| row.price.to_d }
    expect(prices).to eq({ 1 => 336.to_d, 2 => 480.to_d, 3 => 630.to_d, 4 => 780.to_d })
  end

  # M8: reopening an Auto plan shows Auto, with its anchor and steps.
  it "M8: reopening an Auto plan shows it as Auto, with the ladder inputs kept" do
    prm = create(:rate_plan, :custom, hotel: hotel, name: "Promo", ta_access: "hidden", room_type: suite)
    save_auto!(prm, anchor: 480, primary_occupancy: 2, increase_by: 150, increase_unit: "amount", decrease_by: 30, decrease_unit: "percent")

    open_pricing(prm)

    expect(page).to have_checked_field("Generate from a starting rate")
    click_button "Continue"
    expect(page).to have_field("Primary occupancy", with: "2")
    click_button "Continue"
    expect(page).to have_field("Rate at primary occupancy", with: "480.0")
    click_button "Continue"
    expect(page).to have_field("Increase by", with: "150.0")
    click_button "Continue"
    expect(page).to have_field("Decrease by", with: "30.0")
  end

  # M9: a large Auto decrease clamps at 0, not negative, and still saves
  it "M9: an Auto decrease bigger than the anchor clamps the low end at 0" do
    plan = create(:rate_plan, :custom, hotel: hotel, name: "Auto Clamp", ta_access: "hidden", room_type: suite)
    open_pricing(plan)

    choose "Generate from a starting rate"
    fill_in "Primary occupancy", with: "2"
    click_button "Continue"
    fill_in "Rate at primary occupancy", with: "100"
    click_button "Continue"
    fill_in "Increase by", with: "0"
    click_button "Continue"
    fill_in "Decrease by", with: "300"
    select "MYR", from: "Decrease unit"
    save

    expect(page).to have_css("h1", wait: 10)
    expect(page).not_to have_text(/error|problem/i)
    assignment = plan.room_type_rate_plans.find_by!(room_type: suite)
    price_1a = assignment.occupancy_prices.find_by!(adults: 1).price.to_d
    expect(price_1a).to eq(0.to_d)
  end

  private

  def save_manual_std!
    pricing = HotelPortal::RatePlanRoomPricing.from_h(
      { "rate_mode" => "manual", "prices" => { "1" => "250", "2" => "440", "3" => "600", "4" => "740" } },
      room_type: suite, sells_per_person: true
    )
    RatePlans::SaveRoomPricing.call!(rate_plan: std_plan, room_type: suite, pricing: pricing)
  end

  def save_derived!(plan, value)
    pricing = HotelPortal::RatePlanRoomPricing.from_h(
      { "rate_mode" => "derived", "derive_mode" => "multiplier", "derive_value" => value },
      room_type: suite, sells_per_person: true
    )
    RatePlans::SaveRoomPricing.call!(rate_plan: plan, room_type: suite, pricing: pricing)
  end

  def save_auto!(plan, anchor:, primary_occupancy:, increase_by:, increase_unit:, decrease_by:, decrease_unit:)
    pricing = HotelPortal::RatePlanRoomPricing.from_h(
      { "rate_mode" => "auto", "default_rate" => anchor, "primary_occupancy" => primary_occupancy,
        "increase_by" => increase_by, "increase_unit" => increase_unit,
        "decrease_by" => decrease_by, "decrease_unit" => decrease_unit },
      room_type: suite, sells_per_person: true
    )
    RatePlans::SaveRoomPricing.call!(rate_plan: plan, room_type: suite, pricing: pricing)
  end
end
