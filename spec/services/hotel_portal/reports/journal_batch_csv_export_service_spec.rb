require 'rails_helper'

RSpec.describe HotelPortal::Reports::JournalBatchCsvExportService, type: :service do
  let(:hotel) { create(:hotel) }
  let(:batch) { create(:journal_batch, hotel: hotel, business_date: Date.current, finalized_at: Time.current) }

  before do
    create(:journal_batch_entry, journal_batch: batch, gl_code: '4010', transaction_type: 'charge', credit_amount: 100.0)
    create(:journal_batch_entry, journal_batch: batch, gl_code: '1000', transaction_type: 'payment', debit_amount: 100.0)
  end

  describe '#generate' do
    it 'generates a CSV with batch entries' do
      service = described_class.new(batches: [ batch ])
      csv_data = service.generate

      parsed_csv = CSV.parse(csv_data, headers: true)
      expect(parsed_csv.length).to eq(2)
      expect(parsed_csv[0]['General Ledger Code (GL Code)']).to eq('4010')
      expect(parsed_csv[0]['Credit']).to eq('100.0')
      expect(parsed_csv[1]['General Ledger Code (GL Code)']).to eq('1000')
      expect(parsed_csv[1]['Debit']).to eq('100.0')
    end
  end
end
