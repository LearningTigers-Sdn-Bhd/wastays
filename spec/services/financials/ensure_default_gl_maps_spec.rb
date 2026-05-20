require 'rails_helper'

RSpec.describe Financials::EnsureDefaultGlMaps, type: :service do
  let(:hotel) { create(:hotel) }

  describe '.call' do
    it 'creates 7 default GL mappings for the hotel' do
      # The after_create callback already calls this service.
      # So we expect 7 mappings to already exist.
      expect(hotel.hotel_general_ledger_maps.count).to eq(7)

      # We can delete them and run it again to verify it recreates them.
      hotel.hotel_general_ledger_maps.destroy_all
      expect {
        described_class.call(hotel)
      }.to change { hotel.hotel_general_ledger_maps.count }.from(0).to(7)
    end

    it 'is idempotent and does not create duplicates' do
      expect {
        described_class.call(hotel)
      }.not_to change { hotel.hotel_general_ledger_maps.count }
    end

    it 'assigns correct default codes and descriptions' do
      described_class.call(hotel)

      accommodation = hotel.hotel_general_ledger_maps.find_by(transaction_category: 'accommodation')
      expect(accommodation.gl_code).to eq('4010')
      expect(accommodation.description).to eq('Room Revenue')

      tax = hotel.hotel_general_ledger_maps.find_by(transaction_category: 'tax')
      expect(tax.gl_code).to eq('2010')
      expect(tax.description).to eq('Tax Liabilities')
    end
  end
end
