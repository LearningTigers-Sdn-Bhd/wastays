require 'rails_helper'

RSpec.describe BookingEngine::AvailabilityService do
  let!(:account) { Account.create!(name: "Test Account", slug: "test-account", status: "active") }
  let!(:hotel) do
    Hotel.create!(
      sell_mode: RSpec.current_example.metadata[:per_person] ? "per_person" : "per_room",
      name: "Test Hotel", city: "Kuala Lumpur", country: "Malaysia", account: account, status: "approved"
    )
  end
  let!(:room_type) { RoomType.create!(hotel: hotel, name: "Deluxe", quantity: 5, max_adults: 2, base_price: 100, room_number_mode: "range") }

  let(:check_in) { Date.today }
  let(:check_out) { Date.today + 2.days }
  let(:stay_dates) { (check_in...check_out).to_a }

  before do
    # Ensure room_type has its auto-created Standard Rate plan
    standard_plan = room_type.rate_plans.first
    stay_dates.each do |date|
      RoomInventory.create!(room_type: room_type, date: date, quantity: 5, status: "open")
      # Create rates for both nil plan and standard plan
      RoomRate.create!(room_type: room_type, rate_plan: nil, date: date, price: 100, currency: "MYR")
      RoomRate.create!(room_type: room_type, rate_plan: standard_plan, date: date, price: 100, currency: "MYR")
    end
  end

  describe "#find_available_hotels" do
    it "returns the hotel when city and availability match" do
      service = described_class.new(city: "Kuala Lumpur", check_in: check_in, check_out: check_out, adults: 2)
      expect(service.find_available_hotels).to include(hotel)
    end

    it "does not return the hotel if city does not match" do
      service = described_class.new(city: "Singapore", check_in: check_in, check_out: check_out, adults: 2)
      expect(service.find_available_hotels).not_to include(hotel)
    end

    it "does not return the hotel if no inventory" do
      RoomInventory.delete_all
      service = described_class.new(city: "Kuala Lumpur", check_in: check_in, check_out: check_out, adults: 2)
      expect(service.find_available_hotels).not_to include(hotel)
    end
  end

  describe "#available_rooms_for_hotel" do
    it "returns room type if availability exists" do
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.available_rooms_for_hotel(hotel)).to include(room_type)
    end

    it "returns empty if quantity is zero" do
      RoomInventory.update_all(quantity: 0)
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.available_rooms_for_hotel(hotel)).to be_empty
    end

    it "returns empty if status is closed" do
      RoomInventory.update_all(status: 'closed')
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.available_rooms_for_hotel(hotel)).to be_empty
    end

    it "returns empty when the requested children exceed the room category capacity" do
      room_type.update!(max_children: 0)
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 1, children: 1, child_ages: [ 8 ])

      expect(service.available_rooms_for_hotel(hotel)).to be_empty
    end
  end

  describe "#calculate_total_price" do
    it "sums up rates correctly" do
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.calculate_total_price(room_type)).to eq(200.0) # 100 * 2 nights
    end

    it "falls back to room_type.base_price if RoomRate is missing" do
      RoomRate.delete_all
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.calculate_total_price(room_type)).to eq(200.0) # 100 (base) * 2 nights
    end

    it "fails if both RoomRate and base_price are missing" do
      RoomRate.delete_all
      room_type.update_columns(base_price: nil)
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.calculate_total_price(room_type)).to eq(0)
    end

    it "respects stop_sell even if base_price exists" do
      # Apply stop sell to all rates (including those for Standard Rate plan)
      RoomRate.update_all(stop_sell: true)
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.calculate_total_price(room_type)).to eq(0)
    end

    it "respects stop_sell on Standard Rate Plan when calculating base rate fallback" do
      # Only standard plan is stop sell, nil plan has no RoomRate record
      RoomRate.where(rate_plan_id: nil).delete_all
      RoomRate.where(rate_plan_id: room_type.rate_plans.first.id).update_all(stop_sell: true)

      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.calculate_total_price(room_type)).to eq(0)
      expect(service.available_rooms_for_hotel(hotel)).to be_empty
    end

    it "does not offer Corporate plans to anonymous guests" do
      stay_dates.each { |date| create(:room_rate, room_type:, rate_plan: room_type.corporate_rate_plan, date:, price: 80) }
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.calculate_total_price(room_type)).to eq(200.0) # 100 * 2 nights
    end

    it "offers the real Corporate plan when corporate_rate is true" do
      stay_dates.each { |date| create(:room_rate, room_type:, rate_plan: room_type.corporate_rate_plan, date:, price: 80) }
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2, corporate_rate: true)
      expect(service.calculate_total_price(room_type)).to eq(160.0) # 80 * 2 nights
    end
  end

  describe "#calculate_total_price with derived room-type pricing" do
    let(:rate_plan) { RatePlan.create!(hotel: hotel, name: "Non-Refundable", currency: "MYR") }

    it "computes a multiplier off the room type's own Standard Rate price for that date" do
      RoomTypeRatePlan.create!(room_type: room_type, rate_plan: rate_plan, pricing_mode: "multiplier", pricing_value: -10)

      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      # Standard Rate is 100 both nights (per top-level before block) -10% = 90 * 2 nights = 180
      expect(service.calculate_total_price(room_type, rate_plan: rate_plan, adults: 2)).to eq(180.0)
    end

    it "applies a flat offset off the anchor price" do
      RoomTypeRatePlan.create!(room_type: room_type, rate_plan: rate_plan, pricing_mode: "offset", pricing_value: 25)

      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.calculate_total_price(room_type, rate_plan: rate_plan, adults: 2)).to eq(250.0) # (100 + 25) * 2 nights
    end

    it "lets an explicit RoomRate for the derived rate plan win over derivation" do
      RoomTypeRatePlan.create!(room_type: room_type, rate_plan: rate_plan, pricing_mode: "offset", pricing_value: 25)
      RoomRate.create!(room_type: room_type, rate_plan: rate_plan, date: check_in, price: 60, currency: "MYR")

      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      # Night 1 explicit: 60. Night 2 derived: 100 + 25 = 125. Total 185.
      expect(service.calculate_total_price(room_type, rate_plan: rate_plan, adults: 2)).to eq(185.0)
    end

    it "leaves fixed-mode rate plans unaffected (regression guard)" do
      RoomTypeRatePlan.create!(room_type: room_type, rate_plan: rate_plan, pricing_mode: "fixed")

      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.calculate_total_price(room_type, rate_plan: rate_plan, adults: 2)).to eq(200.0) # falls back to base_price, unchanged
    end
  end

  describe "#allocation_options_for_hotel" do
    let!(:small_room) { RoomType.create!(hotel: hotel, name: "Single", quantity: 2, max_adults: 1, base_price: 50, room_number_mode: "range") }

    before do
      stay_dates.each do |date|
        RoomInventory.create!(room_type: small_room, date: date, quantity: 2, status: "open")
        RoomRate.create!(room_type: small_room, rate_plan: nil, date: date, price: 50, currency: "MYR")
      end
    end

    it "finds single-type allocation for large groups" do
      # 5 pax -> needs 2x Deluxe (cap 3) or 5x Single (cap 1)
      # But only 5x Single exists.
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 5)
      options = service.allocation_options_for_hotel(hotel)

      # Option 1: 2x Deluxe (price 100 * 2 * 2 = 400)
      # Option 2: 5x Single (Not possible, only 2 quantity)
      expect(options.first.rooms.first.room_type).to eq(room_type)
      expect(options.first.rooms.first.quantity).to eq(2)
    end

    it "finds mixed-type allocation using greedy approach" do
      # 3 pax -> could be 2x Deluxe (cap 2) OR 1x Deluxe + 1x Single
      # Deluxe price 100, Single price 50
      # 2x Deluxe = 200/night
      # 1x Deluxe + 1x Single = 150/night
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 3)
      options = service.allocation_options_for_hotel(hotel)

      prices = options.map(&:total_price)
      expect(prices).to include(300.0) # 1x Deluxe + 1x Single (150 * 2 nights)
      expect(prices).to include(400.0) # 2x Deluxe (200 * 2 nights)
    end
  end

  describe "#allocation_options_for_hotel (Per Person with Single Supplement)", :per_person do
    let!(:pax_rate_plan) { RatePlan.create!(hotel: hotel, name: "Per Person Plan", single_supplement: 20.0, currency: "MYR") }

    before do
      pax_rate_plan.reload
      # Link pax_rate_plan to room_type
      RoomTypeRatePlan.create!(room_type: room_type, rate_plan: pax_rate_plan)
      # Setup rates on the pax plan
      stay_dates.each do |date|
        RoomRate.create!(room_type: room_type, rate_plan: pax_rate_plan, date: date, price: 40.0, currency: "MYR")
      end
    end

    it "allocates 3 guests into two 2-capacity rooms, distributing them as 2 and 1 with a single supplement" do
      # 3 pax -> 2 rooms of type Deluxe (capacity 2).
      # Room 1 occupancy = 2. Nightly price = 40 * 2 = 80.
      # Room 2 occupancy = 1. Nightly price = 40 * 1 + 20 supplement = 60.
      # Total nightly = 140. For 2 nights = 280.
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 3)
      options = service.allocation_options_for_hotel(hotel)

      # Under standard rate (100 per room):
      #   2 rooms * 100 * 2 nights = 400.
      # Under pax plan:
      #   (Room 1: 80 * 2) + (Room 2: 60 * 2) = 160 + 120 = 280.
      # Cheaper option should be chosen first!
      best_option = options.first
      expect(best_option.total_price).to eq(280.0)
      expect(best_option.rooms.size).to eq(2) # One group of 2, one group of 1

      pax_2_room = best_option.rooms.find { |r| r.pax == 2 }
      pax_1_room = best_option.rooms.find { |r| r.pax == 1 }

      expect(pax_2_room.quantity).to eq(1)
      expect(pax_2_room.price_per_room).to eq(160.0) # 80 * 2 nights

      expect(pax_1_room.quantity).to eq(1)
      expect(pax_1_room.price_per_room).to eq(120.0) # 60 * 2 nights
    end
  end

  describe "#calculate_total_price with age-banded per_person rate plan", :per_person do
    let!(:family_room) { RoomType.create!(hotel: hotel, name: "Family", quantity: 3, max_adults: 2, max_children: 3, base_price: 100, room_number_mode: "range") }
    let!(:pax_rate_plan) { RatePlan.create!(hotel: hotel, name: "Age Banded Plan", child_price_multiplier: 0.6, currency: "MYR") }

    before do
      pax_rate_plan.reload
      RoomTypeRatePlan.create!(room_type: family_room, rate_plan: pax_rate_plan)
      RatePlanAgeBand.create!(rate_plan: pax_rate_plan, min_age: 4, max_age: 11, price_value: 40, label: "Child")
      RatePlanAgeBand.create!(rate_plan: pax_rate_plan, min_age: 12, max_age: 17, price_value: 20, label: "Teen")

      stay_dates.each do |date|
        RoomInventory.create!(room_type: family_room, date: date, quantity: 3, status: "open")
        RoomRate.create!(room_type: family_room, rate_plan: pax_rate_plan, date: date, price: 50.0, currency: "MYR")
      end
    end

    it "prices each child individually by their resolved age band" do
      # 2 adults @ 50 + 1 child(6) @ 50*0.4 + 1 child(15) @ 50*0.2 = 100 + 20 + 10 = 130/night, 2 nights = 260
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2, children: 2, child_ages: [ 6, 15 ])
      total = service.calculate_total_price(family_room, rate_plan: pax_rate_plan, adults: 2, children: 2, child_ages: [ 6, 15 ])

      expect(total).to eq(260.0)
    end

    it "falls back to the flat child_price_multiplier when no ages are supplied (regression guard)" do
      # 2 adults @ 50 + 2 children @ 50*0.6 = 100 + 60 = 160/night, 2 nights = 320
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2, children: 2)
      total = service.calculate_total_price(family_room, rate_plan: pax_rate_plan, adults: 2, children: 2)

      expect(total).to eq(320.0)
    end

    it "falls back to the flat child_price_multiplier for an age not covered by any band" do
      # child age 1 falls in a gap -> flat multiplier 0.6 applies
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2, children: 1, child_ages: [ 1 ])
      total = service.calculate_total_price(family_room, rate_plan: pax_rate_plan, adults: 2, children: 1, child_ages: [ 1 ])

      # 2 adults @ 50 + 1 child @ 50*0.6 = 130/night, 2 nights = 260
      expect(total).to eq(260.0)
    end

    it "ignores mismatched child_ages (count mismatch) and falls back to the flat multiplier" do
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2, children: 2, child_ages: [ 6 ])
      total = service.calculate_total_price(family_room, rate_plan: pax_rate_plan, adults: 2, children: 2, child_ages: [ 6 ])

      expect(total).to eq(320.0)
    end

    it "prices a flat-amount band regardless of the nightly rate" do
      RatePlanAgeBand.create!(rate_plan: pax_rate_plan, min_age: 0, max_age: 3, pricing_mode: "amount", price_value: 15.0, label: "Infant")
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2, children: 1, child_ages: [ 2 ])
      total = service.calculate_total_price(family_room, rate_plan: pax_rate_plan, adults: 2, children: 1, child_ages: [ 2 ])

      # 2 adults @ 50 + 1 flat-amount child @ 15 = 115/night, 2 nights = 230
      expect(total).to eq(230.0)
    end
  end

  describe "callers that do not name an occupancy", :per_person do
    # Search and the room cards ask for a price without repeating the party.
    # They must get the searched adults/children/ages, not the headcount
    # collapsed into adults — which skips child pricing and asks the occupancy
    # matrix for an adult row that was never configured.
    let!(:family_room) { RoomType.create!(hotel: hotel, name: "Family", quantity: 3, max_adults: 2, max_children: 2, base_price: 200, room_number_mode: "range") }
    let!(:pax_rate_plan) { RatePlan.create!(hotel: hotel, name: "Per-Pax Plan", child_price_multiplier: 0.5, currency: "MYR") }

    before do
      pax_rate_plan.reload
      RoomTypeRatePlan.create!(room_type: family_room, rate_plan: pax_rate_plan)
      RatePlanAgeBand.create!(rate_plan: pax_rate_plan, min_age: 4, max_age: 11, price_value: 40, label: "Child")

      stay_dates.each do |date|
        RoomInventory.create!(room_type: family_room, date: date, quantity: 3, status: "open")
        # Every plan on a per-person room carries the matrix, so no plan has a
        # row for 4 adults — exactly the setup that used to drop the room.
        [ pax_rate_plan, family_room.standard_rate_plan ].compact.each do |plan|
          RoomRate.create!(
            room_type: family_room, rate_plan: plan, date: date,
            price: 300.0, currency: "MYR",
            occupancy_prices: { "1" => 180.0, "2" => 300.0 }
          )
        end
      end
    end

    it "keeps a room whose matrix has no row for the collapsed headcount" do
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2, children: 2, child_ages: [ 6, 6 ])

      expect(service.available_rooms_for_hotel(hotel)).to include(family_room)
    end

    it "prices the searched family rather than 4 adults" do
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2, children: 2, child_ages: [ 6, 6 ])

      # 2 adults @ 300 + 2 children @ (300/2)*0.4 = 300 + 120 = 420/night, 2 nights
      expect(service.pricing_summary_for(family_room)[:total_price]).to eq(840.0)
    end

    it "still honours an explicitly named occupancy" do
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2, children: 2, child_ages: [ 6, 6 ])

      expect(service.calculate_total_price(family_room, adults: 1, children: 0)).to eq(360.0)
    end
  end

  describe "#allocation_options_for_hotel groups rooms by child ages, not just counts", :per_person do
    let!(:pax_rate_plan) { RatePlan.create!(hotel: hotel, name: "Age Banded Plan", child_price_multiplier: 1.0, currency: "MYR") }
    let!(:room_a) { RoomType.create!(hotel: hotel, name: "Room A", quantity: 2, max_adults: 1, max_children: 1, base_price: 100, room_number_mode: "range") }

    before do
      pax_rate_plan.reload
      RoomTypeRatePlan.create!(room_type: room_a, rate_plan: pax_rate_plan)
      RatePlanAgeBand.create!(rate_plan: pax_rate_plan, min_age: 0, max_age: 5, price_value: 10, label: "Toddler")
      RatePlanAgeBand.create!(rate_plan: pax_rate_plan, min_age: 13, max_age: 17, price_value: 90, label: "Teen")

      stay_dates.each do |date|
        RoomInventory.create!(room_type: room_a, date: date, quantity: 2, status: "open")
        RoomRate.create!(room_type: room_a, rate_plan: pax_rate_plan, date: date, price: 100.0, currency: "MYR")
      end
    end

    it "prices two same-headcount rooms with different child ages independently, not batched together" do
      # 2 adults, 2 children (ages 2 and 16) split across 2 rooms of capacity 2 (1 adult + 1 child each).
      # Room 1: adult @ 100 + child(2) @ 100*0.1 = 110/night
      # Room 2: adult @ 100 + child(16) @ 100*0.9 = 190/night
      # Total nightly = 300, 2 nights = 600 (NOT 2x110 or 2x190, which would happen if incorrectly batched)
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2, children: 2, child_ages: [ 2, 16 ], room_count: 2)
      options = service.allocation_options_for_hotel(hotel)

      best = options.min_by(&:total_price)
      expect(best.total_price).to eq(600.0)
      expect(best.rooms.size).to eq(2)
      expect(best.rooms.map(&:quantity)).to all(eq(1))
    end
  end

  describe "#available_rooms_for_hotel with restrictions" do
    let(:tomorrow) { Date.current + 1.day }
    let(:check_out_date) { tomorrow + 1.day } # 1 night stay

    it "returns empty when allow_restricted is false for min stay" do
      RoomRate.update_all(min_stay: 3)
      service = described_class.new(check_in: tomorrow.to_s, check_out: check_out_date.to_s, adults: 2)
      expect(service.available_rooms_for_hotel(hotel, allow_restricted: false)).to be_empty
    end

    it "returns room type when allow_restricted is true for min stay" do
      RoomRate.update_all(min_stay: 3)
      service = described_class.new(check_in: tomorrow.to_s, check_out: check_out_date.to_s, adults: 2)
      expect(service.available_rooms_for_hotel(hotel, allow_restricted: true)).to include(room_type)
      expect(service.stay_restriction_error_message(room_type)).to include("Minimum stay is 3 night(s)")
    end

    it "returns empty when allow_restricted is false for CTA" do
      RoomRate.update_all(min_stay: nil, closed_to_arrival: true)
      service = described_class.new(check_in: tomorrow.to_s, check_out: check_out_date.to_s, adults: 2)
      expect(service.available_rooms_for_hotel(hotel, allow_restricted: false)).to be_empty
    end

    it "returns room type when allow_restricted is true for CTA" do
      RoomRate.update_all(min_stay: nil, closed_to_arrival: true)
      service = described_class.new(check_in: tomorrow.to_s, check_out: check_out_date.to_s, adults: 2)
      expect(service.available_rooms_for_hotel(hotel, allow_restricted: true)).to include(room_type)
      expect(service.stay_restriction_error_message(room_type)).to include("Check-in is not allowed")
    end

    it "returns empty when allow_restricted is false for CTD" do
      RoomRate.update_all(min_stay: nil, closed_to_departure: true)
      service = described_class.new(check_in: tomorrow.to_s, check_out: check_out_date.to_s, adults: 2)
      expect(service.available_rooms_for_hotel(hotel, allow_restricted: false)).to be_empty
    end

    it "returns room type when allow_restricted is true for CTD" do
      RoomRate.update_all(min_stay: nil, closed_to_departure: true)
      service = described_class.new(check_in: tomorrow.to_s, check_out: check_out_date.to_s, adults: 2)
      expect(service.available_rooms_for_hotel(hotel, allow_restricted: true)).to include(room_type)
      expect(service.stay_restriction_error_message(room_type)).to include("Check-out is not allowed")
    end
  end

  describe "#candidate_rate_plans_for" do
    let!(:pax_rate_plan) { RatePlan.create!(hotel: hotel, name: "Per Person Plan", single_supplement: 20.0, currency: "MYR") }

    before do
      RoomTypeRatePlan.create!(room_type: room_type, rate_plan: pax_rate_plan)
    end

    context "when the hotel sells per room" do
      it "returns only real bookable rate plans" do
        service = described_class.new(check_in: check_in, check_out: check_out, adults: 1)
        plans = service.send(:candidate_rate_plans_for, room_type)
        expect(plans).not_to include(nil)
        expect(plans).to include(pax_rate_plan)
        expect(plans).to include(room_type.rate_plans.first)
      end

      it "never offers a special tier plan" do
        walk_in = create(:rate_plan, :walk_in_tier, hotel: hotel)
        RoomTypeRatePlan.create!(room_type: room_type, rate_plan: walk_in)

        service = described_class.new(check_in: check_in, check_out: check_out, adults: 1)
        expect(service.send(:candidate_rate_plans_for, room_type)).not_to include(walk_in)
      end
    end

    context "when the hotel sells per guest", :per_person do
      before do
        pax_rate_plan.reload
      end

      it "returns the bookable rate plans and excludes nil" do
        service = described_class.new(check_in: check_in, check_out: check_out, adults: 1)
        plans = service.send(:candidate_rate_plans_for, room_type)
        expect(plans).not_to include(nil)
        expect(plans).to include(pax_rate_plan)
      end

      it "never offers a special tier plan" do
        walk_in = create(:rate_plan, :walk_in_tier, hotel: hotel)
        RoomTypeRatePlan.create!(room_type: room_type, rate_plan: walk_in)

        service = described_class.new(check_in: check_in, check_out: check_out, adults: 1)
        expect(service.send(:candidate_rate_plans_for, room_type)).not_to include(walk_in)
      end
    end
  end
end
