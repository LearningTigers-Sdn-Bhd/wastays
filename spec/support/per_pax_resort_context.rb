# frozen_string_literal: true

# Shared world for the per-pax rate plan / travel agent test plan
# (docs/wastays/per-pax-ta-reservations-test-plan-2026-09-25.md). Built through
# the same services the UI uses (RatePlans::SaveRoomPricing,
# HotelPortal::RatePlanRoomPricing) so prices are stored exactly as the rate
# plan page stores them.
RSpec.shared_context "per-pax resort" do
  let(:hotel) { create(:hotel, :per_person, status: "live", tourism_tax_enabled: true, tourism_tax_amount: 10) }

  let!(:suite) do
    Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "Pax Family Suite", room_number_mode: "custom", quantity: 3,
                    base_price: 150.0, max_adults: 4, max_children: 2, room_numbers: %w[F1 F2 F3] }
    )
  end

  let!(:twin) do
    Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "Pax Deluxe Twin", room_number_mode: "custom", quantity: 2,
                    base_price: 200.0, max_adults: 2, max_children: 1, room_numbers: %w[T1 T2] }
    )
  end

  let(:std_plan) { suite.standard_rate_plan }

  # Rooms::SaveSeedRoomType already ran RatePlans::EnsureSystemPlans, which
  # dedicates one Corporate Rate (kind "corporate") to this room type. Reuse
  # it as CORP instead of creating a second corporate-kind plan, which would
  # otherwise sit alongside CORP in every corporate-audience query (both kinds
  # match AUDIENCE_KINDS[:corporate]) and pollute every visibility assertion.
  let(:corp_plan) { suite.rate_plans.find_by!(kind: "corporate") }

  let!(:fb_plan) do
    plan = create(:rate_plan, :custom, hotel: hotel, name: "Full Board", ta_access: "hidden")
    create(:rate_plan_age_band, rate_plan: plan, min_age: 4, max_age: 11, pricing_mode: "multiplier", price_value: 40, label: "Child", position: 1)
    create(:rate_plan_age_band, rate_plan: plan, min_age: 12, max_age: 17, pricing_mode: "amount", price_value: 150, label: "Teen", position: 2)
    plan.rate_plan_stay_discounts.create!(min_nights: 3, discount_type: "percent", value: 10, from_night: 1)
    plan.rate_plan_stay_discounts.create!(min_nights: 5, discount_type: "amount", value: 20, from_night: 2)
    plan
  end

  let!(:prm_plan) do
    create(:rate_plan, :custom, hotel: hotel, name: "Promo", ta_access: "all")
  end

  let!(:staff_plan) do
    create(:rate_plan, :custom, hotel: hotel, name: "Staff Only", ta_access: "hidden")
  end

  let!(:ota_plan) do
    create(:rate_plan, :ota_tier, hotel: hotel, name: "OTA")
  end

  # --- Suite occupancy prices, saved through the same form the rate plan page uses ---

  def save_manual_prices!(plan, room_type, prices)
    pricing = HotelPortal::RatePlanRoomPricing.from_h(
      { "rate_mode" => "manual", "prices" => prices.transform_keys(&:to_s) },
      room_type: room_type, sells_per_person: true
    )
    RatePlans::SaveRoomPricing.call!(rate_plan: plan, room_type: room_type, pricing: pricing)
  end

  def save_derived_prices!(plan, room_type, derive_value:, derive_mode: "multiplier")
    pricing = HotelPortal::RatePlanRoomPricing.from_h(
      { "rate_mode" => "derived", "derive_mode" => derive_mode, "derive_value" => derive_value },
      room_type: room_type, sells_per_person: true
    )
    RatePlans::SaveRoomPricing.call!(rate_plan: plan, room_type: room_type, pricing: pricing)
  end

  def save_auto_prices!(plan, room_type, anchor:, primary_occupancy: 2, increase_by: 0, increase_unit: "amount", decrease_by: 0, decrease_unit: "amount")
    pricing = HotelPortal::RatePlanRoomPricing.from_h(
      { "rate_mode" => "auto", "default_rate" => anchor, "primary_occupancy" => primary_occupancy,
        "increase_by" => increase_by, "increase_unit" => increase_unit,
        "decrease_by" => decrease_by, "decrease_unit" => decrease_unit },
      room_type: room_type, sells_per_person: true
    )
    RatePlans::SaveRoomPricing.call!(rate_plan: plan, room_type: room_type, pricing: pricing)
  end

  before do
    # STD Suite: 1A 250 | 2A 440 | 3A 600 | 4A 740
    save_manual_prices!(std_plan, suite, { 1 => 250, 2 => 440, 3 => 600, 4 => 740 })
    # FB Suite: 1A 300 | 2A 500 | 3A 690 | 4A 840
    save_manual_prices!(fb_plan, suite, { 1 => 300, 2 => 500, 3 => 690, 4 => 840 })
    # CORP Suite: derived -10% of STD
    save_derived_prices!(corp_plan, suite, derive_value: -10)
    # PRM Suite: auto, anchor 480 @ 2 adults, +150 amount / extra, -30% / fewer
    save_auto_prices!(prm_plan, suite, anchor: 480, primary_occupancy: 2,
                                        increase_by: 150, increase_unit: "amount",
                                        decrease_by: 30, decrease_unit: "percent")
    # STAFF Suite: same as STD
    save_manual_prices!(staff_plan, suite, { 1 => 250, 2 => 440, 3 => 600, 4 => 740 })

    # Twin (max 2A/1C): STD and FB only, needed for capacity edge cases
    save_manual_prices!(std_plan, twin, { 1 => 200, 2 => 350 })
    save_manual_prices!(fb_plan, twin, { 1 => 260, 2 => 430 })

    # Tourism tax needs a tax rule wired to Room Revenue (TransactionCodes::AssignTaxRules) -
    # tourism_tax_enabled alone doesn't put it on any folio.
    room_revenue_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    room_revenue_code.update!(is_taxable: true)
    TransactionCodes::AssignTaxRules.call(transaction_code: room_revenue_code, keys: [ "primary:tourism_tax" ])

    # TA access. std_plan and corp_plan are system plans (EnsureSystemPlans);
    # std_plan defaults to ta_access "hidden" and corp_plan to "all" - set
    # explicitly to match the test world (§5).
    std_plan.update!(ta_access: "all")
    fb_plan.update!(ta_access: "only", agency_account_ids: [ ta_a.id ])
    corp_plan.update!(ta_access: "except", agency_account_ids: [ ta_c.id ])
  end

  # --- Travel agents ---

  let(:ta_a_user) { create(:user, :corporate) }
  let!(:ta_a) do
    create(:hotel_corporate_account, hotel: hotel, corporate_account: ta_a_user.account,
                                      account_type: "travel_agent", agent_booking_enabled: true)
  end

  let(:ta_b_user) { create(:user, :corporate) }
  let!(:ta_b) do
    create(:hotel_corporate_account, :direct_bill, hotel: hotel, corporate_account: ta_b_user.account,
                                                    account_type: "travel_agent", agent_booking_enabled: true)
  end

  let(:ta_c_user) { create(:user, :corporate) }
  let!(:ta_c) do
    create(:hotel_corporate_account, hotel: hotel, corporate_account: ta_c_user.account,
                                      account_type: "travel_agent", agent_booking_enabled: true)
  end

  let(:ta_d_user) { create(:user, :corporate) }
  let!(:ta_d) do
    create(:hotel_corporate_account, hotel: hotel, corporate_account: ta_d_user.account,
                                      account_type: "travel_agent", agent_booking_enabled: true,
                                      status: "suspended")
  end
end
