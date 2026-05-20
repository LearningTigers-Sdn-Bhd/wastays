require 'rails_helper'

RSpec.describe Financials::CreateJournalBatch, type: :service do
  let(:hotel) { create(:hotel) }
  let(:business_date) { Date.current }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:folio) { create(:booking_folio, hotel: hotel, booking: booking) }

  before do
    # Set up GL mappings
    hotel.hotel_general_ledger_maps.find_by(transaction_category: 'accommodation').update!(gl_code: 'REV-ROOM')
    hotel.hotel_general_ledger_maps.find_by(transaction_category: 'tax').update!(gl_code: 'TAX-LIAB')
    hotel.hotel_general_ledger_maps.find_by(transaction_category: 'gateway_payment').update!(gl_code: 'BANK-GATEWAY')
    hotel.hotel_general_ledger_maps.find_by(transaction_category: 'adjustment').update!(gl_code: 'ADJ-WRITE')

    # Create transactions for the business date
    # 1. Accommodation Charge (Revenue)
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: 'charge',
      category: 'accommodation',
      amount: 200.0,
      posting_date: business_date
    )

    # 2. Tax Charge (Revenue)
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: 'charge',
      category: 'tax',
      amount: 20.0,
      posting_date: business_date
    )

    # 3. Payment (Debit to Bank)
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: 'payment',
      category: 'gateway_payment',
      amount: 220.0,
      posting_date: business_date
    )

    # 4. Adjustment (Debit to Expense/Write-off)
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: 'adjustment',
      category: 'adjustment',
      amount: -10.0,
      posting_date: business_date
    )
  end

  describe '.call' do
    it 'creates a finalized journal batch for the hotel and business date' do
      batch = described_class.call(hotel: hotel, business_date: business_date)

      expect(batch).to be_persisted
      expect(batch.hotel).to eq(hotel)
      expect(batch.business_date).to eq(business_date)
      expect(batch.status).to eq('finalized')
      expect(batch.finalized_at).to be_within(1.minute).of(Time.current)
    end

    it 'groups transactions by GL code and transaction type' do
      batch = described_class.call(hotel: hotel, business_date: business_date)

      expect(batch.entries.count).to eq(4)

      # Verify Accommodation (Credit Revenue)
      acc_entry = batch.entries.find_by(gl_code: 'REV-ROOM')
      expect(acc_entry.credit_amount).to eq(200.0)
      expect(acc_entry.debit_amount).to eq(0)

      # Verify Tax (Credit Liability)
      tax_entry = batch.entries.find_by(gl_code: 'TAX-LIAB')
      expect(tax_entry.credit_amount).to eq(20.0)
      expect(tax_entry.debit_amount).to eq(0)

      # Verify Payment (Debit Bank)
      pay_entry = batch.entries.find_by(gl_code: 'BANK-GATEWAY')
      expect(pay_entry.debit_amount).to eq(220.0)
      expect(pay_entry.credit_amount).to eq(0)

      # Verify Adjustment (Debit Expense for negative adjustment)
      adj_entry = batch.entries.find_by(gl_code: 'ADJ-WRITE')
      expect(adj_entry.debit_amount).to eq(10.0)
      expect(adj_entry.credit_amount).to eq(0)
    end

    it 'updates summary_data jsonb column' do
      batch = described_class.call(hotel: hotel, business_date: business_date)

      expect(batch.summary_data['total_transactions']).to eq(4)
      expect(batch.summary_data['gl_summaries']['REV-ROOM']).to eq({ 'debit' => "0.0", 'credit' => "200.0" })
    end

    it 'idempotently recreates entries if called multiple times' do
      described_class.call(hotel: hotel, business_date: business_date)
      expect(JournalBatch.count).to eq(1)
      expect(JournalBatchEntry.count).to eq(4)

      described_class.call(hotel: hotel, business_date: business_date)
      expect(JournalBatch.count).to eq(1)
      expect(JournalBatchEntry.count).to eq(4)
    end
  end
end
