# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::SaveRatesAvailability do
  let(:hotel) { create(:hotel) }
  let(:actor) { create(:user, account: hotel.account) }
  let(:room) { create(:room_type, hotel: hotel, quantity: 2, max_adults: 2, base_price: 0) }

  def complete_prerequisites(target, target_actor)
    Onboarding::InitializeProgress.new(hotel: target, actor: target_actor).call
    %w[property_profile roles_permissions staff_setup taxes_fees room_revenue rooms].each do |key|
      target.onboarding_sections.find_by!(section_key: key).update!(state: "complete")
    end
  end

  before do
    room
    complete_prerequisites(hotel, actor)
  end

  def params(price: "120", custom_plans: {}, weekend_uplift: nil)
    {
      "start_date" => Date.current.to_s,
      "end_date" => (Date.current + 364.days).to_s,
      "weekend_days" => %w[0 6],
      "weekend_uplift" => weekend_uplift || { "adjustment_mode" => "percent", "adjustment_value" => "0" },
      "standard_entries" => {
        "standard" => {
          "room_type_id" => room.id.to_s,
          "base_occupancy" => "2",
          "extra_pax_charge" => "25",
          "default_rate" => price
        }
      },
      "custom_plans" => custom_plans,
      "availability_entries" => {
        "0" => { "room_type_id" => room.id.to_s, "quantity" => "2", "status" => "open" }
      }
    }
  end

  it "atomically completes Standard pricing and one-year availability" do
    result = described_class.call(hotel: hotel, actor: actor, params: params, complete: true)

    expect(result).to be_success
    expect(room.reload.base_price).to eq(120)
    # Occupancy rules land on the pairing, not the plan, so one plan can cover
    # rooms that include different numbers of pax.
    assignment = room.room_type_rate_plans.find_by(rate_plan: room.standard_rate_plan)
    expect(assignment).to have_attributes(base_occupancy: 2, extra_pax_charge: 25)
    expect(room.room_inventories.where(date: Date.current..Date.current + 364.days).count).to eq(365)
    expect(result.coverage).to have_attributes(configured_percentage: 100, sellable_percentage: 100)
    expect(hotel.onboarding_sections.find_by!(section_key: "rates_availability").state).to eq("complete")
  end

  it "rolls every domain change back when completion pricing is invalid" do
    result = described_class.call(hotel: hotel, actor: actor, params: params(price: "0"), complete: true)

    expect(result).not_to be_success
    expect(room.reload.base_price).to eq(0)
    expect(room.room_inventories).to be_empty
    expect(hotel.onboarding_sections.find_by!(section_key: "rates_availability").state).to eq("not_started")
  end

  describe "plan-level pricing basis" do
    let(:second_room) { create(:room_type, hotel: hotel, quantity: 1, max_adults: 2, base_price: 0) }

    def derived_plan(rooms)
      {
        "new" => {
          "name" => "Advance Purchase",
          "rate_mode" => "derived_multiplier",
          "derive_value" => "-10",
          "assignments" => rooms.each_with_index.to_h do |assigned, index|
            [ "row-#{index}", { "room_type_id" => assigned.id.to_s } ]
          end
        }
      }
    end

    it "writes the plan's one basis to every room assigned to it" do
      submitted = params(custom_plans: derived_plan([ room, second_room ]))
      submitted["standard_entries"]["second"] = {
        "room_type_id" => second_room.id.to_s, "default_rate" => "150"
      }
      submitted["availability_entries"]["1"] = {
        "room_type_id" => second_room.id.to_s, "quantity" => "1", "status" => "open"
      }

      result = described_class.call(hotel: hotel, actor: actor, params: submitted, complete: true)

      expect(result).to be_success
      plan = hotel.rate_plans.find_by!(kind: "custom", name: "Advance Purchase")
      expect(plan.room_type_rate_plans.count).to eq(2)
      expect(plan.room_type_rate_plans).to all(have_attributes(pricing_mode: "multiplier", pricing_value: -10))
    end

    # The point of the per-pairing columns: one plan, two rooms, two different
    # ideas of what the room rate includes.
    it "keeps each room's occupancy rules separate under one shared plan" do
      custom = {
        "new" => {
          "name" => "Corporate", "rate_mode" => "manual",
          "assignments" => {
            "row-0" => { "room_type_id" => room.id.to_s, "default_rate" => "99",
                         "base_occupancy" => "2", "extra_pax_charge" => "25" },
            "row-1" => { "room_type_id" => second_room.id.to_s, "default_rate" => "199",
                         "base_occupancy" => "4", "extra_pax_charge" => "40" }
          }
        }
      }
      submitted = params(custom_plans: custom)
      submitted["standard_entries"]["second"] = {
        "room_type_id" => second_room.id.to_s, "base_occupancy" => "2",
        "extra_pax_charge" => "25", "default_rate" => "150"
      }
      submitted["availability_entries"]["1"] = {
        "room_type_id" => second_room.id.to_s, "quantity" => "1", "status" => "open"
      }

      result = described_class.call(hotel: hotel, actor: actor, params: submitted, complete: true)

      expect(result).to be_success
      plan = hotel.rate_plans.find_by!(kind: "custom", name: "Corporate")
      by_room = plan.room_type_rate_plans.index_by(&:room_type_id)
      expect(by_room[room.id]).to have_attributes(base_occupancy: 2, extra_pax_charge: 25)
      expect(by_room[second_room.id]).to have_attributes(base_occupancy: 4, extra_pax_charge: 40)
    end

    it "leaves the pairing deferring to the plan when a row states no rule" do
      custom = {
        "new" => {
          "name" => "Corporate", "rate_mode" => "manual",
          "assignments" => { "row-0" => { "room_type_id" => room.id.to_s, "default_rate" => "99" } }
        }
      }

      result = described_class.call(hotel: hotel, actor: actor, params: params(custom_plans: custom), complete: true)

      expect(result).to be_success
      assignment = hotel.rate_plans.find_by!(kind: "custom", name: "Corporate").room_type_rate_plans.sole
      expect(assignment.base_occupancy).to be_nil
      expect(assignment.effective_base_occupancy).to eq(assignment.rate_plan.base_occupancy)
    end

    it "prices directly when the plan is not derived" do
      custom = {
        "new" => {
          "name" => "Corporate", "rate_mode" => "manual",
          "assignments" => { "row-0" => { "room_type_id" => room.id.to_s, "default_rate" => "99" } }
        }
      }

      result = described_class.call(hotel: hotel, actor: actor, params: params(custom_plans: custom), complete: true)

      expect(result).to be_success
      plan = hotel.rate_plans.find_by!(kind: "custom", name: "Corporate")
      expect(plan.room_type_rate_plans.sole).to have_attributes(pricing_mode: "fixed", pricing_value: 99)
    end
  end

  describe "weekend uplift" do
    it "applies one property-wide figure to every room and plan on the chosen days" do
      result = described_class.call(
        hotel: hotel, actor: actor, complete: true,
        params: params(weekend_uplift: { "adjustment_mode" => "percent", "adjustment_value" => "10" })
      )

      expect(result).to be_success
      weekend = RoomRate.where(room_type: room, applied_rule_type: "onboarding_weekend")
      expect(weekend.count).to be_positive
      expect(weekend.pluck(:date).map(&:wday).uniq).to match_array([ 0, 6 ])
      expect(weekend.first.price).to eq(132)
    end

    it "writes no dated rates when the uplift is zero" do
      result = described_class.call(hotel: hotel, actor: actor, params: params, complete: true)

      expect(result).to be_success
      expect(RoomRate.where(room_type: room, applied_rule_type: "onboarding_weekend")).to be_empty
    end
  end

  describe "child age bands" do
    let(:pax_hotel) { create(:hotel, :per_person, account: hotel.account) }
    let(:pax_room) { create(:room_type, hotel: pax_hotel, quantity: 2, max_adults: 2, base_price: 0) }

    def pax_params(bands:, custom_plans: {})
      {
        "start_date" => Date.current.to_s,
        "end_date" => (Date.current + 364.days).to_s,
        "weekend_days" => %w[0 6],
        "weekend_uplift" => { "adjustment_mode" => "percent", "adjustment_value" => "0" },
        "child_bands" => bands,
        "standard_entries" => {
          "standard" => {
            "room_type_id" => pax_room.id.to_s,
            "prices" => { "1" => "100", "2" => "180" }
          }
        },
        "custom_plans" => custom_plans,
        "availability_entries" => {
          "0" => { "room_type_id" => pax_room.id.to_s, "quantity" => "2", "status" => "open" }
        }
      }
    end

    def full_bands
      {
        "0" => { "min_age" => "0", "max_age" => "2", "price_value" => "0", "label" => "Infant" },
        "1" => { "min_age" => "3", "max_age" => "11", "price_value" => "60", "label" => "Child" },
        "2" => { "min_age" => "12", "max_age" => "17", "price_value" => "90", "label" => "Teen" }
      }
    end

    before do
      pax_room
      complete_prerequisites(pax_hotel, actor)
    end

    it "writes the same amount-priced bands to every rate plan" do
      custom = {
        "new" => {
          "name" => "Advance Purchase", "rate_mode" => "manual",
          "assignments" => { "row-0" => { "room_type_id" => pax_room.id.to_s, "prices" => { "1" => "90", "2" => "160" } } }
        }
      }

      result = described_class.call(
        hotel: pax_hotel, actor: actor, complete: true,
        params: pax_params(bands: full_bands, custom_plans: custom)
      )

      expect(result).to be_success

      plans = pax_hotel.rate_plans.where(kind: %w[standard custom])
      expect(plans.count).to be >= 2
      plans.each do |plan|
        expect(plan.rate_plan_age_bands.map { |band| [ band.min_age, band.max_age, band.price_value, band.pricing_mode ] })
          .to eq([ [ 0, 2, 0, "amount" ], [ 3, 11, 60, "amount" ], [ 12, 17, 90, "amount" ] ])
      end
    end

    it "rejects a gap, because an unpriced age silently falls through to the adult rate" do
      gapped = full_bands.merge("1" => { "min_age" => "4", "max_age" => "11", "price_value" => "60", "label" => "Child" })

      result = described_class.call(hotel: pax_hotel, actor: actor, params: pax_params(bands: gapped), complete: true)

      expect(result).not_to be_success
      expect(result.error).to match(/overlap or leave a gap/)
    end

    it "rejects bands that stop short of the oldest child age" do
      short = full_bands.except("2")

      result = described_class.call(hotel: pax_hotel, actor: actor, params: pax_params(bands: short), complete: true)

      expect(result).not_to be_success
      expect(result.error).to match(/must cover ages 0–17/)
    end

    it "rejects more bands than the setup screen offers" do
      too_many = full_bands.merge(
        "1" => { "min_age" => "3", "max_age" => "5", "price_value" => "40", "label" => "A" },
        "2" => { "min_age" => "6", "max_age" => "9", "price_value" => "50", "label" => "B" },
        "3" => { "min_age" => "10", "max_age" => "13", "price_value" => "60", "label" => "C" },
        "4" => { "min_age" => "14", "max_age" => "17", "price_value" => "70", "label" => "D" }
      )

      result = described_class.call(hotel: pax_hotel, actor: actor, params: pax_params(bands: too_many), complete: true)

      expect(result).not_to be_success
      expect(result.error).to match(/at most 4 child age bands/)
    end

    # Per-room pricing charges children as extra pax and never reads bands, so
    # saving them there would be a number that silently does nothing.
    it "ignores bands entirely for a per-room property" do
      submitted = params.merge("child_bands" => full_bands)

      result = described_class.call(hotel: hotel, actor: actor, params: submitted, complete: true)

      expect(result).to be_success
      expect(RatePlanAgeBand.where(rate_plan: hotel.rate_plans)).to be_empty
    end
  end

  it "reconfirms rates and marks completed downstream setup for review after a material save" do
    first = described_class.call(hotel: hotel, actor: actor, params: params, complete: true)
    expect(first).to be_success
    downstream = hotel.onboarding_sections.find_by!(section_key: "channel_manager")
    downstream.update!(state: "complete", completed_at: Time.current)

    result = described_class.call(hotel: hotel, actor: actor, params: params(price: "135"), complete: true)

    expect(result).to be_success
    expect(hotel.onboarding_sections.find_by!(section_key: "rates_availability").state).to eq("complete")
    expect(downstream.reload.state).to eq("needs_attention")
    expect(hotel.onboarding_audit_events.where(section_key: "channel_manager", event_type: "invalidated")).to exist
  end
end
