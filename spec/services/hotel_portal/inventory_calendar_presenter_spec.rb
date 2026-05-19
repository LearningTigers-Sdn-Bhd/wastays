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
end
