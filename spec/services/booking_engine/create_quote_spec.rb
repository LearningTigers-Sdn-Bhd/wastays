require 'rails_helper'

RSpec.describe BookingEngine::CreateQuote do
  let!(:account) { Account.create!(name: "Test Account", slug: "test-account", status: "active") }
  let!(:hotel) { Hotel.create!(name: "Test Hotel", city: "Kuala Lumpur", country: "Malaysia", account: account, status: "approved", allow_pax_pricing: true) }
  let!(:room_type) { RoomType.create!(hotel: hotel, name: "Deluxe", quantity: 5, max_adults: 2, base_price: 100, room_number_mode: "range") }

  let(:check_in) { Date.today }
  let(:check_out) { Date.today + 2.days }
  let(:stay_dates) { (check_in...check_out).to_a }

  before do
    stay_dates.each do |date|
      RoomInventory.create!(room_type: room_type, date: date, quantity: 5, status: "open")
      RoomRate.create!(room_type: room_type, date: date, price: 100, currency: "MYR")
    end
  end

  describe "#call" do
    let(:params) { { hotel_id: hotel.id, room_type_id: room_type.id, check_in: check_in, check_out: check_out, adults: 2 } }

    it "creates a quote and holds inventory" do
      service = described_class.new(params)
      result = service.call

      expect(result.success?).to be true
      expect(result.quote).to be_persisted
      expect(result.quote.booking_quote_items.count).to eq(1)

      stay_dates.each do |date|
        expect(room_type.room_inventories.find_by(date: date).quantity).to eq(4)
      end
    end

    it "stores display currency snapshot separately from charge currency" do
      create(:exchange_rate, base_currency: "MYR", currency_code: "USD", rate: 0.25)
      service = described_class.new(params.merge(display_currency: "USD"))
      result = service.call

      expect(result.success?).to be true
      expect(result.quote.currency).to eq("MYR")
      expect(result.quote.total_amount).to eq(200)
      expect(result.quote.display_currency).to eq("USD")
      expect(result.quote.display_total_amount).to eq(50)
      expect(result.quote.display_exchange_rate).to eq(0.25)
      expect(result.quote.display_rate_source).to eq("managed_fx")
    end

    it "fails if room is no longer available" do
      RoomInventory.update_all(quantity: 0)
      service = described_class.new(params)
      result = service.call

      expect(result.success?).to be false
      expect(result.message).to eq("Room Deluxe is no longer available.")
    end

    it "fails with clear error when dates are missing" do
      service = described_class.new(
        hotel_id: hotel.id,
        room_type_id: room_type.id,
        check_in: "",
        check_out: "",
        adults: "",
        children: "",
        room_count: "1"
      )
      result = service.call

      expect(result.success?).to be false
      expect(result.message).to eq("Please select check-in and check-out dates.")
    end

    context "when a selected rate plan has stay-length restrictions" do
      let(:rate_plan) { create(:rate_plan, room_type: room_type, name: "2-4 Night Rate", currency: "MYR") }

      before do
        stay_dates.each do |date|
          RoomRate.create!(
            room_type: room_type,
            rate_plan: rate_plan,
            date: date,
            price: 120,
            currency: "MYR",
            min_stay: 2,
            max_stay: 4
          )
        end
      end

      context "when the stay is shorter than the minimum" do
        let(:check_out) { check_in + 1.day }

        it "rejects quote creation" do
          result = described_class.new(params.merge(rate_plan_id: rate_plan.id)).call

          expect(result.success?).to be false
          expect(result.message).to eq("No valid rate for room #{room_type.name} with selected occupancy.")
        end
      end

      context "when the stay is longer than the maximum" do
        let(:check_out) { check_in + 5.days }

        it "rejects quote creation" do
          result = described_class.new(params.merge(rate_plan_id: rate_plan.id)).call

          expect(result.success?).to be false
          expect(result.message).to eq("No valid rate for room #{room_type.name} with selected occupancy.")
        end
      end

      context "when the stay length is within the allowed range" do
        let(:check_out) { check_in + 3.days }

        it "allows quote creation" do
          result = described_class.new(params.merge(rate_plan_id: rate_plan.id)).call

          expect(result.success?).to be true
          expect(result.quote).to be_persisted
          expect(result.quote.total_amount).to eq(360)
        end
      end
    end

    it "fails if total guests exceed maximum capacity of the allocated rooms" do
      # Capacity of Deluxe room_type is 2. Booking requests 3 adults for 1 room.
      service = described_class.new(params.merge(adults: 3))
      result = service.call

      expect(result.success?).to be false
      expect(result.message).to include("do not have enough capacity")
    end

    context "with per_person pricing plan" do
      let!(:pax_rate_plan) { RatePlan.create!(hotel: hotel, name: "Per Person Plan", sell_mode: "per_person", single_supplement: 15.0, currency: "MYR") }

      before do
        RoomTypeRatePlan.create!(room_type: room_type, rate_plan: pax_rate_plan)
        stay_dates.each do |date|
          RoomRate.create!(room_type: room_type, rate_plan: pax_rate_plan, date: date, price: 30.0, currency: "MYR")
        end
      end

      it "calculates correct per-person quote with single occupancy supplement" do
        # 1 guest -> Room occupancy is 1.
        # Nightly rate = 30 * 1 + 15 supplement = 45.
        # Total for 2 nights = 90.
        service = described_class.new(params.merge(adults: 1, rate_plan_id: pax_rate_plan.id))
        result = service.call

        expect(result.success?).to be true
        expect(result.quote.total_amount).to eq(90.0)
        expect(result.quote.booking_quote_items.first.occupancy_snapshot["actual_occupancy"]).to eq(1)
      end

      it "calculates correct per-person quote for multi-room group with distributed occupancy" do
        # 3 guests in 2 rooms -> Room 1 has 2 guests, Room 2 has 1 guest.
        # Room 1: 30 * 2 = 60/night.
        # Room 2: 30 * 1 + 15 = 45/night.
        # Total nightly = 105. For 2 nights = 210.
        service = described_class.new(
          hotel_id: hotel.id,
          allocations: [ { room_type_id: room_type.id, quantity: 2 } ],
          check_in: check_in,
          check_out: check_out,
          adults: 3,
          rate_plan_id: pax_rate_plan.id
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.quote.total_amount).to eq(210.0)

        items = result.quote.booking_quote_items
        expect(items.count).to eq(2) # Group of 2 pax and Group of 1 pax
        expect(items.map { |i| i.occupancy_snapshot["actual_occupancy"] }).to contain_exactly(2, 1)
      end

      it "fails if there are not enough adults to supervise each room (at least 1 adult per room)" do
        # Requests 2 rooms, but only 1 adult is provided
        service = described_class.new(
          hotel_id: hotel.id,
          allocations: [ { room_type_id: room_type.id, quantity: 2 } ],
          check_in: check_in,
          check_out: check_out,
          adults: 1,
          children: 2
        )
        result = service.call

        expect(result.success?).to be false
        expect(result.message).to include("require more adults to supervise each room")
      end

      it "respects explicit room count for flexible guest layouts (e.g. 3 guests in 3 rooms)" do
        # 3 adults requesting room_count: 3. Should distribute as [1, 1, 1] instead of [2, 1]
        service = described_class.new(
          hotel_id: hotel.id,
          allocations: [ { room_type_id: room_type.id, quantity: 3 } ],
          check_in: check_in,
          check_out: check_out,
          adults: 3,
          room_count: 3,
          rate_plan_id: pax_rate_plan.id
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.quote.booking_quote_items.count).to eq(1) # 1 item since all have same occupancy 1
        expect(result.quote.booking_quote_items.first.quantity).to eq(3) # 3 rooms
        expect(result.quote.booking_quote_items.first.occupancy_snapshot["actual_occupancy"]).to eq(1)
        expect(result.quote.total_amount).to eq(270.0) # 3 rooms * (30 * 1 pax + 15 supplement) * 2 nights = 3 * 45 * 2 = 270.0
      end
    end

    context "with age-banded per_person pricing plan" do
      let!(:family_room) { RoomType.create!(hotel: hotel, name: "Family", quantity: 3, max_adults: 2, max_children: 3, base_price: 100, room_number_mode: "range") }
      let!(:pax_rate_plan) { RatePlan.create!(hotel: hotel, name: "Age Banded Plan", sell_mode: "per_person", child_price_multiplier: 0.6, currency: "MYR") }

      before do
        RoomTypeRatePlan.create!(room_type: family_room, rate_plan: pax_rate_plan)
        RatePlanAgeBand.create!(rate_plan: pax_rate_plan, min_age: 4, max_age: 11, price_value: 40, label: "Child")
        RatePlanAgeBand.create!(rate_plan: pax_rate_plan, min_age: 12, max_age: 17, price_value: 20, label: "Teen")

        stay_dates.each do |date|
          RoomInventory.create!(room_type: family_room, date: date, quantity: 3, status: "open")
          RoomRate.create!(room_type: family_room, rate_plan: pax_rate_plan, date: date, price: 50.0, currency: "MYR")
        end
      end

      it "freezes the resolved age -> band -> multiplier mapping into occupancy_snapshot at quote time" do
        # 2 adults @ 50 + 1 child(6) @ 50*0.4 + 1 child(15) @ 50*0.2 = 100 + 20 + 10 = 130/night, 2 nights = 260
        service = described_class.new(
          hotel_id: hotel.id,
          allocations: [ { room_type_id: family_room.id, quantity: 1 } ],
          check_in: check_in,
          check_out: check_out,
          adults: 2,
          children: 2,
          child_ages: [ 6, 15 ],
          room_count: 1,
          rate_plan_id: pax_rate_plan.id
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.quote.total_amount).to eq(260.0)

        snapshot = result.quote.booking_quote_items.first.occupancy_snapshot
        expect(snapshot["child_ages"]).to contain_exactly(6, 15)

        bands = snapshot["child_age_bands"]
        child_band = bands.find { |b| b["age"] == 6 }
        teen_band = bands.find { |b| b["age"] == 15 }
        expect(child_band["band_label"]).to eq("Child")
        expect(child_band["pricing_mode"]).to eq("multiplier")
        expect(child_band["price_value"]).to eq("40.0")
        expect(teen_band["band_label"]).to eq("Teen")
        expect(teen_band["price_value"]).to eq("20.0")
      end

      it "falls back to the flat child_price_multiplier and empty child_ages when no ages are supplied" do
        service = described_class.new(
          hotel_id: hotel.id,
          allocations: [ { room_type_id: family_room.id, quantity: 1 } ],
          check_in: check_in,
          check_out: check_out,
          adults: 2,
          children: 2,
          room_count: 1,
          rate_plan_id: pax_rate_plan.id
        )
        result = service.call

        expect(result.success?).to be true
        # 2 adults @ 50 + 2 children @ 50*0.6 = 160/night, 2 nights = 320
        expect(result.quote.total_amount).to eq(320.0)

        snapshot = result.quote.booking_quote_items.first.occupancy_snapshot
        expect(snapshot["child_ages"]).to eq([])
      end
    end
  end
end
