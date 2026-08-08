require 'rails_helper'

RSpec.describe HotelPortal::InventoryCalendarPresenter do
  let(:hotel) { create(:hotel, default_currency: "MYR") }
  let(:start_date) { Date.current }
  let(:end_date) { start_date + 6.days }
  let(:presenter) { described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "MYR") }

  describe '#dates' do
    it 'returns the range of dates' do
      expect(presenter.dates.size).to eq(7)
      expect(presenter.dates.first).to eq(start_date)
    end
  end

  describe '#format_price' do
    it 'formats price with currency symbol and handles decimals' do
      expect(presenter.send(:format_price, 200)).to eq("200.00")
      expect(presenter.send(:format_price, 200.5)).to eq("200.50")
      expect(presenter.send(:format_price, 200.55)).to eq("200.55")
    end

    it 'uses $ for USD' do
      p = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "USD")
      expect(p.send(:format_price, 100)).to eq("100.00")
    end
  end

  describe '#rows' do
    it 'filters out walk-in named rate plans from regular rows' do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Twin", room_numbers: [ "101" ], quantity: 1)
      # room_type already has one "Standard Rate" plan from after_create callback
      create(:rate_plan, :walk_in_tier, room_type: room_type, currency: "MYR")

      presenter = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "MYR")

      rate_labels = presenter.rows.select(&:rate_row?).map(&:sublabel)

      expect(rate_labels).to contain_exactly("Standard Rate")
      expect(presenter.rows.select(&:walk_in_row?).size).to eq(1)
    end

    it 'identifies special tiers by kind, so a renamed tier stays a tier' do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Twin")
      create(:rate_plan, :walk_in_tier, room_type: room_type, name: "Rack Rate", currency: "MYR")

      presenter = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "MYR")

      expect(presenter.rows.select(&:rate_row?).map(&:sublabel)).to contain_exactly("Standard Rate")
    end

    it 'keeps an ordinary plan named like a tier as an ordinary row' do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Twin")
      create(:rate_plan, :custom, room_type: room_type, name: "Corporate", currency: "MYR")

      presenter = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "MYR")

      expect(presenter.rows.select(&:rate_row?).map(&:sublabel)).to contain_exactly("Standard Rate", "Corporate")
    end

    it 'leaves archived plans out of the grid and the filter list' do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Twin")
      archived = create(:rate_plan, :custom, room_type: room_type, name: "Last Season", currency: "MYR")
      archived.archive!

      presenter = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "MYR")

      expect(presenter.rows.select(&:rate_row?).map(&:sublabel)).to contain_exactly("Standard Rate")
      expect(presenter.rate_plan_options_struct.map(&:id)).not_to include(archived.id)
    end

    it 'no longer offers an OTA tier, which has no column to store a price' do
      create(:room_type, hotel: hotel, name: "Deluxe Twin")

      presenter = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "MYR")

      expect(presenter.rate_plan_options_struct.map(&:id).grep(/tier_ota/)).to be_empty
    end
  end

  describe '#cell_for' do
    it "shows the same derived nightly price used by bookings" do
      room_type = create(:room_type, hotel: hotel, base_price: 100)
      standard = room_type.standard_rate_plan
      package = create(:rate_plan, :custom, hotel: hotel, name: "Breakfast Package", currency: "MYR")
      create(:room_type_rate_plan, room_type: room_type, rate_plan: package, pricing_mode: "offset", pricing_value: 25)
      create(:room_rate, room_type: room_type, rate_plan: standard, date: start_date, price: 200, currency: "MYR")

      presenter = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "MYR")
      row = presenter.rows.find { |item| item.rate_row? && item.rate_plan_id == package.id }

      expect(presenter.cell_for(row, start_date)).to include(
        formatted_price: "225.00",
        price_source: :standard_daily_rate
      )
    end

    it "shows a fixed plan's persisted starting price when the date has no override" do
      room_type = create(:room_type, hotel: hotel, base_price: 100)
      package = create(:rate_plan, :custom, hotel: hotel, name: "Flexible", currency: "MYR")
      create(:room_type_rate_plan, room_type: room_type, rate_plan: package, pricing_mode: "fixed", pricing_value: 175)

      presenter = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "MYR")
      row = presenter.rows.find { |item| item.rate_row? && item.rate_plan_id == package.id }

      expect(presenter.cell_for(row, start_date)).to include(
        formatted_price: "175.00",
        price_source: :starting_price
      )
    end

    it "exposes each per-guest occupancy price and displays the room's maximum-adult price" do
      hotel.update!(sell_mode: "per_person")
      room_type = create(:room_type, hotel: hotel, max_adults: 2, base_price: 100)
      package = create(:rate_plan, :custom, hotel: hotel, name: "Flexible", currency: "MYR")
      assignment = create(:room_type_rate_plan, room_type: room_type, rate_plan: package, pricing_mode: "fixed")
      assignment.occupancy_prices.create!(adults: 1, price: 180)
      assignment.occupancy_prices.create!(adults: 2, price: 300)

      presenter = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "MYR")
      row = presenter.rows.find { |item| item.rate_row? && item.rate_plan_id == package.id }

      expect(presenter.cell_for(row, start_date)).to include(
        formatted_price: "300.00",
        display_adults: 2,
        occupancy_prices: { "1" => 180.to_d, "2" => 300.to_d }
      )
    end

    it 'falls back to the standard rate for walk-in and corporate rows when special prices are missing' do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Twin", room_numbers: [ "101" ], quantity: 1)
      rate_plan = room_type.rate_plans.first # Use auto-created Standard Rate plan
      rate_plan.update!(name: "Standard Rate") # Ensure it has the right name if needed
      create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: start_date, currency: "MYR", price: 150, walk_in_price: nil, corporate_price: nil)

      presenter = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "MYR")

      walk_in_row = presenter.rows.find(&:walk_in_row?)
      corporate_row = presenter.rows.find(&:corporate_row?)

      expect(presenter.cell_for(walk_in_row, start_date)[:formatted_price]).to eq("150.00")
      expect(presenter.cell_for(corporate_row, start_date)[:formatted_price]).to eq("150.00")
    end

    context 'with one rate plan shared across room categories' do
      let!(:coral) { create(:room_type, hotel: hotel, name: "Coral Villa", base_price: 3300) }
      let!(:pool) { create(:room_type, hotel: hotel, name: "Pool Villa", base_price: 4800) }
      let!(:package) { create(:rate_plan, :custom, hotel: hotel, name: "All Inclusive Package", room_type: coral, currency: "MYR") }

      before do
        create(:room_type_rate_plan, rate_plan: package, room_type: pool)

        create(:room_rate, room_type: coral, rate_plan: package, date: start_date, currency: "MYR", price: 1350, min_stay: 2)
        create(:room_rate, room_type: pool, rate_plan: package, date: start_date, currency: "MYR", price: 1600, min_stay: 5)
      end

      it 'shows each category its own price' do
        presenter = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "MYR")

        prices = presenter.rows.select { |row| row.rate_row? && row.rate_plan_id == package.id }.to_h do |row|
          [ row.room_type.name, presenter.cell_for(row, start_date)[:formatted_price] ]
        end

        expect(prices).to eq("Coral Villa" => "1,350.00", "Pool Villa" => "1,600.00")
      end

      it 'shows each category its own restrictions' do
        presenter = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "MYR")

        badges = presenter.rows.select { |row| row.rate_row? && row.rate_plan_id == package.id }.to_h do |row|
          [ row.room_type.name, presenter.cell_for(row, start_date)[:restriction_compact] ]
        end

        expect(badges).to eq("Coral Villa" => "MIN2", "Pool Villa" => "MIN5")
      end
    end
  end

  describe "sold counts" do
    it "correctly counts bookings even when check_in/check_out are TimeWithZone" do
      room_type = create(:room_type, hotel: hotel, quantity: 5)
      # Create a booking that spans 2 nights
      check_in = Time.zone.parse("#{start_date} 14:00:00")
      check_out = Time.zone.parse("#{start_date + 2.days} 12:00:00")

      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: check_in, check_out: check_out)
      create(:booking_room, booking: booking, room_type: room_type)

      presenter = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "MYR")
      row = presenter.rows.find { |r| r.inventory_row? && r.room_type_id == room_type.id }

      # Should count 1 for start_date and start_date + 1.day
      expect(presenter.cell_for(row, start_date)[:sold_count]).to eq(1)
      expect(presenter.cell_for(row, start_date + 1.day)[:sold_count]).to eq(1)
      expect(presenter.cell_for(row, start_date + 2.days)[:sold_count]).to eq(0)
    end
  end

  describe '#sold_counts_by_room_type' do
    it 'correctly calculates sold counts using date ranges even when database check_in/check_out are time-zoned' do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Twin", room_numbers: [ "101" ], quantity: 5)
      booking = create(:booking, hotel: hotel, check_in: start_date, check_out: start_date + 2.days, status: "confirmed")
      create(:booking_room, booking: booking, room_type: room_type)

      # Re-initialize presenter to capture the new room type and booking
      presenter = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "MYR")

      sold_counts = presenter.send(:sold_counts_by_room_type)

      expect(sold_counts[room_type.id][start_date]).to eq(1)
      expect(sold_counts[room_type.id][start_date + 1.day]).to eq(1)
      expect(sold_counts[room_type.id][start_date + 2.days]).to eq(0)
    end
  end

  describe 'channel mapping rows filtering' do
    let(:room_type_mapped) { create(:room_type, hotel: hotel, name: "Mapped Room") }
    let(:room_type_unmapped) { create(:room_type, hotel: hotel, name: "Unmapped Room") }

    let(:channel_data) do
      {
        "id" => "chan-123",
        "type" => "channel",
        "attributes" => {
          "title" => "BookingCom",
          "channel" => "BookingCom",
          "settings" => {
            "mappingSettings" => {
              "rooms" => {
                "ota_room_id" => "ext-rt-mapped"
              }
            }
          }
        }
      }
    end

    before do
      hotel.update!(preferred_channel_manager: "channex")
      # Setup mapping for mapped room
      create(:channel_mapping, mappable: room_type_mapped, provider: "channex", external_id: "ext-rt-mapped")
      # Setup pending mapping for unmapped room
      create(:channel_mapping, mappable: room_type_unmapped, provider: "channex", external_id: "pending-rt")
    end

    it 'only includes summary and availability rows for mapped room types' do
      allow(presenter).to receive(:connected_channels).and_return([ channel_data ])

      # Find summary rows
      summary_rows = presenter.rows.select(&:channel_summary_row?)
      expect(summary_rows.map(&:room_type_id)).to contain_exactly(room_type_mapped.id)

      # Find availability rows
      availability_rows = presenter.rows.select(&:channel_availability_row?)
      expect(availability_rows.map(&:room_type_id)).to contain_exactly(room_type_mapped.id)
    end
  end
end
