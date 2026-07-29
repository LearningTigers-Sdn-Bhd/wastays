require "rails_helper"

RSpec.describe AiConcierge::Tools::Booking::SearchBookingOptionsTool do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe Room", max_adults: 2) }

  def create_availability(room_type, date:, price: 200, quantity: 2, rate_plan: nil)
    create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: date, price: price, currency: "MYR")
    create(:room_inventory, room_type: room_type, date: date, quantity: quantity, status: "open")
  end

  def count_sql_queries
    queries = []
    callback = lambda do |_name, _started, _finished, _unique_id, payload|
      next if payload[:cached]
      next if %w[SCHEMA TRANSACTION].include?(payload[:name])

      queries << payload[:sql]
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      yield
    end

    queries.count
  end

  before do
    [ 11, 12, 13, 14 ].each_with_index do |day, index|
      date = Date.new(2026, 8, day)
      create_availability(room_type, date: date, price: 200 + index)
    end
  end

  it "returns grouped options with room type names and selection ids" do
    result = described_class.new(
      hotel: hotel,
      target_month: 8,
      target_year: 2026,
      month_segment: "mid",
      adults: 2,
      children: 0,
      room_count: 1,
      nights: 2
    ).call

    expect(result).not_to be_empty
    expect(result.first["room_type_id"]).to eq(room_type.id)
    expect(result.first["room_type_name"]).to eq("Deluxe Room")
    expect(result.first.dig("options", 0, "position")).to eq(1)
    expect(result.first.dig("options", 0, "selection_id")).to be_present
  end

  context "alignment across room types" do
    let!(:room_type_a) { create(:room_type, hotel: hotel, name: "Room A", max_adults: 2) }
    let!(:room_type_b) { create(:room_type, hotel: hotel, name: "Room B", max_adults: 2) }

    before do
      # Room A available May 21..28
      # Room B available May 24..31
      # nights = 3

      (21..31).each do |day|
        date = Date.new(2026, 5, day)
        # Room A
        if day <= 28
          create(:room_rate, room_type: room_type_a, date: date, price: 100)
          create(:room_inventory, room_type: room_type_a, date: date, quantity: 1, status: "open")
        end
        # Room B
        if day >= 24
          create(:room_rate, room_type: room_type_b, date: date, price: 200)
          create(:room_inventory, room_type: room_type_b, date: date, quantity: 1, status: "open")
        end
      end
    end

    it "aligns the date options for both rooms to May 24, 25, 26 (highest common availability)" do
      result = described_class.new(
        hotel: hotel,
        target_month: 5,
        target_year: 2026,
        month_segment: "late",
        adults: 2,
        children: 0,
        room_count: 1,
        nights: 3
      ).call

      group_a = result.find { |g| g["room_type_name"] == "Room A" }
      group_b = result.find { |g| g["room_type_name"] == "Room B" }

      dates_a = group_a["options"].map { |o| o["check_in"] }
      dates_b = group_b["options"].map { |o| o["check_in"] }

      # They should both prioritize May 24, 25, 26 because those dates have 2 rooms available
      # whereas 21, 22, 23 only have 1 room available.
      expect(dates_a).to eq([ "2026-05-24", "2026-05-25", "2026-05-26" ])
      expect(dates_b).to eq([ "2026-05-24", "2026-05-25", "2026-05-26" ])
    end

    it "falls back to individual availability if a room is not available on aligned dates" do
      room_type_c = create(:room_type, hotel: hotel, name: "Room C", max_adults: 2)
      # Room C only available May 21, 22
      (21..22).each do |day|
        date = Date.new(2026, 5, day)
        create(:room_rate, room_type: room_type_c, date: date, price: 300)
        create(:room_inventory, room_type: room_type_c, date: date, quantity: 1, status: "open")
      end

      result = described_class.new(
        hotel: hotel,
        target_month: 5,
        target_year: 2026,
        month_segment: "late",
        adults: 2,
        children: 0,
        room_count: 1,
        nights: 1 # shorter stay to make 21, 22 available
      ).call

      group_c = result.find { |g| g["room_type_name"] == "Room C" }
      dates_c = group_c["options"].map { |o| o["check_in"] }

      # Best dates will still be 24, 25, 26 because A and B are available then.
      # Room C is not available on 24, 25, 26, so it should fall back to its own dates.
      expect(dates_c).to include("2026-05-21")
      expect(dates_c).to include("2026-05-22")
    end
  end

  context "rate plans and query shape" do
    it "returns all complete rate plans and uses the cheapest plan for option total" do
      standard = create(:rate_plan, room_type: room_type, name: "Standard Rate")
      non_refundable = create(:rate_plan, room_type: room_type, name: "Non-Refundable Rate")

      RoomRate.where(room_type: room_type).delete_all
      [ 11, 12 ].each do |day|
        date = Date.new(2026, 8, day)
        create(:room_rate, room_type: room_type, rate_plan: standard, date: date, price: 150, currency: "MYR")
        create(:room_rate, room_type: room_type, rate_plan: non_refundable, date: date, price: 120, currency: "MYR")
      end

      result = described_class.new(
        hotel: hotel,
        target_month: 8,
        target_year: 2026,
        month_segment: "mid",
        adults: 2,
        children: 0,
        room_count: 1,
        nights: 2
      ).call

      option = result.first.dig("options", 0)

      expect(option["total_price"]).to eq(240)
      expect(option["rate_plans"]).to contain_exactly(
        include("name" => "Standard Rate", "total_price" => 300.to_d, "currency" => "MYR"),
        include("name" => "Non-Refundable Rate", "total_price" => 240.to_d, "currency" => "MYR")
      )
    end

    it "keeps SQL query count bounded as room types and rate plans grow" do
      small_hotel = create(:hotel, :with_ai_concierge)
      large_hotel = create(:hotel, :with_ai_concierge)

      build_search_fixture(hotel: small_hotel, room_type_count: 1, rate_plan_count: 1)
      build_search_fixture(hotel: large_hotel, room_type_count: 5, rate_plan_count: 3)

      small_count = count_sql_queries { run_search(small_hotel) }
      large_count = count_sql_queries { run_search(large_hotel) }

      expect(large_count).to be <= small_count + 1
    end

    def build_search_fixture(hotel:, room_type_count:, rate_plan_count:)
      room_type_count.times do |room_index|
        current_room_type = create(:room_type, hotel: hotel, name: "Query Room #{room_index}", max_adults: 2)
        rate_plans = rate_plan_count.times.map do |plan_index|
          create(:rate_plan, room_type: current_room_type, name: "Plan #{room_index}-#{plan_index}")
        end

        (11..14).each do |day|
          date = Date.new(2026, 8, day)
          create(:room_inventory, room_type: current_room_type, date: date, quantity: 2, status: "open")

          rate_plans.each_with_index do |rate_plan, index|
            create(:room_rate, room_type: current_room_type, rate_plan: rate_plan, date: date, price: 100 + index, currency: "MYR")
          end
        end
      end
    end

    def run_search(hotel)
      described_class.new(
        hotel: hotel,
        target_month: 8,
        target_year: 2026,
        month_segment: "mid",
        adults: 2,
        children: 0,
        room_count: 1,
        nights: 2
      ).call
    end
  end

  describe "pax pricing accuracy" do
    let(:pax_hotel) { create(:hotel, allow_pax_pricing: true, pax_pricing_only: true) }
    let(:pax_room_type) { create(:room_type, hotel: pax_hotel, max_adults: 4, max_children: 2, base_price: 500.0) }
    let(:pax_rate_plan) do
      create(:rate_plan, :age_banded, hotel: pax_hotel, name: "Family Per-Pax", room_type: pax_room_type, base_occupancy: 2, single_supplement: 30)
    end

    def real_quote_total(hotel:, room_type:, rate_plan:, adults:, children:, child_ages: [])
      BookingEngine::CreateQuote.new(
        hotel_id: hotel.id,
        allocations: { "0" => { room_type_id: room_type.id, quantity: 1 } },
        check_in: Date.current, check_out: Date.current + 1,
        adults: adults, children: children, child_ages: child_ages,
        rate_plan_id: rate_plan.id,
        guest_name: "Test Guest", guest_email: "guest@example.com", guest_phone: "0123456789"
      ).call.quote.total_amount
    end

    it "matches the real quote engine for a per-person plan when ages are unknown (both fall back to the flat multiplier)" do
      create(:room_inventory, room_type: pax_room_type, date: Date.current, quantity: 5, status: "open")
      create(:room_rate, room_type: pax_room_type, rate_plan: pax_rate_plan, date: Date.current, price: 100.0)

      tool = described_class.new(
        hotel: pax_hotel, target_month: Date.current.month, target_year: Date.current.year, month_segment: nil,
        check_in: Date.current, check_out: Date.current + 1,
        adults: 2, children: 2, room_count: 1
      )
      preview_total = tool.call.first["options"].first["total_price"]

      expect(preview_total).to eq(real_quote_total(hotel: pax_hotel, room_type: pax_room_type, rate_plan: pax_rate_plan, adults: 2, children: 2))
    end

    it "applies extra_pax_charge for a per-room plan, matching the real quote engine" do
      hotel = create(:hotel, allow_pax_pricing: false)
      room_type = create(:room_type, hotel: hotel, max_adults: 4, max_children: 0, base_price: 150.0)
      rate_plan = create(:rate_plan, hotel: hotel, name: "Standard", sell_mode: "per_room", room_type: room_type, base_occupancy: 2, extra_pax_charge: 25)
      create(:room_inventory, room_type: room_type, date: Date.current, quantity: 5, status: "open")
      create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: Date.current, price: 150.0)

      tool = described_class.new(
        hotel: hotel, target_month: Date.current.month, target_year: Date.current.year, month_segment: nil,
        check_in: Date.current, check_out: Date.current + 1,
        adults: 3, children: 0, room_count: 1
      )
      preview_total = tool.call.first["options"].first["total_price"]

      # 150 base + 1 extra adult over base_occupancy(2) * 25 = 175
      expect(preview_total).to eq(175.0)
    end
  end
end
