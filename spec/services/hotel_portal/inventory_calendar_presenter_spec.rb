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
      create(:rate_plan, room_type: room_type, name: "Walk-in Rate", currency: "MYR")

      presenter = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "MYR")

      rate_labels = presenter.rows.select(&:rate_row?).map(&:sublabel)

      expect(rate_labels).to contain_exactly("Standard Rate")
      expect(presenter.rows.select(&:walk_in_row?).size).to eq(1)
    end
  end

  describe '#cell_for' do
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
