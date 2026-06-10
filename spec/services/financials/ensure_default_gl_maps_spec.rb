require 'rails_helper'

RSpec.describe Financials::EnsureDefaultGlMaps, type: :service do
  let(:hotel) { create(:hotel) }

  describe '.call' do
    it 'creates default General Ledger (GL) mappings for every folio transaction category' do
      # The after_create callback already calls this service.
      expect(hotel.hotel_general_ledger_maps.pluck(:transaction_category)).to match_array(FolioTransaction.gl_mappable_categories)

      # We can delete them and run it again to verify it recreates them.
      hotel.hotel_general_ledger_maps.destroy_all
      expect {
        described_class.call(hotel)
      }.to change { hotel.hotel_general_ledger_maps.count }.from(0).to(FolioTransaction.gl_mappable_categories.count)

      expect(hotel.hotel_general_ledger_maps.pluck(:transaction_category)).to match_array(FolioTransaction.gl_mappable_categories)
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

      booking_payment = hotel.hotel_general_ledger_maps.find_by(transaction_category: 'booking_payment')
      expect(booking_payment.gl_code).to eq('2020')
      expect(booking_payment.description).to eq('Booking Payment Liability')

      security_deposits = hotel.hotel_general_ledger_maps.find_by(transaction_category: 'security_deposits')
      expect(security_deposits.gl_code).to eq('2030')
      expect(security_deposits.description).to eq('Security Deposit Liability')

      write_off = hotel.hotel_general_ledger_maps.find_by(transaction_category: 'write_off')
      expect(write_off.gl_code).to eq('5040')
      expect(write_off.description).to eq('Write-Offs')
    end

    it 'does not overwrite customized existing mappings' do
      hotel.hotel_general_ledger_maps.find_by!(transaction_category: 'accommodation').update!(
        gl_code: 'CUSTOM-ROOM',
        description: 'Custom room revenue'
      )

      described_class.call(hotel)

      accommodation = hotel.hotel_general_ledger_maps.find_by!(transaction_category: 'accommodation')
      expect(accommodation.gl_code).to eq('CUSTOM-ROOM')
      expect(accommodation.description).to eq('Custom room revenue')
    end
  end
end
