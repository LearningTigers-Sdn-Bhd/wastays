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
      expect(presenter.send(:format_price, 200)).to eq("RM 200.00")
      expect(presenter.send(:format_price, 200.5)).to eq("RM 200.50")
      expect(presenter.send(:format_price, 200.55)).to eq("RM 200.55")
    end

    it 'uses $ for USD' do
      p = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "USD")
      expect(p.send(:format_price, 100)).to eq("$ 100.00")
    end
  end

  describe '#rows' do
    it 'filters out walk-in named rate plans from regular rows' do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Twin", room_numbers: [ "101" ], quantity: 1)
      create(:rate_plan, room_type: room_type, name: "Standard Rate", currency: "MYR")
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
      rate_plan = create(:rate_plan, room_type: room_type, name: "Standard Rate", currency: "MYR")
      create(:room_rate, rate_plan: rate_plan, date: start_date, currency: "MYR", price: 150, walk_in_price: nil, corporate_price: nil)

      presenter = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, display_currency: "MYR")

      walk_in_row = presenter.rows.find(&:walk_in_row?)
      corporate_row = presenter.rows.find(&:corporate_row?)

      expect(presenter.cell_for(walk_in_row, start_date)[:formatted_price]).to eq("RM 150.00")
      expect(presenter.cell_for(corporate_row, start_date)[:formatted_price]).to eq("RM 150.00")
    end
  end
end
