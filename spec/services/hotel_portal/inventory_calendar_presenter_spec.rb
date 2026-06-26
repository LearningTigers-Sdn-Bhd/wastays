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
      create(:room_rate, rate_plan: rate_plan, date: start_date, currency: "MYR", price: 150, walk_in_price: nil, corporate_price: nil)

      presenter = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "MYR")

      walk_in_row = presenter.rows.find(&:walk_in_row?)
      corporate_row = presenter.rows.find(&:corporate_row?)

      expect(presenter.cell_for(walk_in_row, start_date)[:formatted_price]).to eq("150.00")
      expect(presenter.cell_for(corporate_row, start_date)[:formatted_price]).to eq("150.00")
    end
  end

  describe "sold counts" do
    it "correctly counts bookings even when check_in/check_out are TimeWithZone" do
      room_type = create(:room_type, hotel: hotel, quantity: 5)
      # Create a booking that spans 2 nights
      check_in = Time.zone.parse("#{start_date} 14:00:00")
      check_out = Time.zone.parse("#{start_date + 2.days} 12:00:00")

      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: check_in, check_out: check_out)
      create(:booking_room, booking: booking, room_type: room_type, quantity: 1)

      presenter = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "MYR")
      row = presenter.rows.find { |r| r.inventory_row? && r.room_type_id == room_type.id }

      # Should count 1 for start_date and start_date + 1.day
      expect(presenter.cell_for(row, start_date)[:sold_count]).to eq(1)
      expect(presenter.cell_for(row, start_date + 1.day)[:sold_count]).to eq(1)
      expect(presenter.cell_for(row, start_date + 2.days)[:sold_count]).to eq(0)
    end
  end
end
