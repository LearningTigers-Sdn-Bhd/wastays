# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Finalize do
  let(:booking) { create(:booking, currency: "MYR") }
  let(:user) { create(:user) }
  let(:folio) { create(:booking_folio, booking:, status: "closed", closed_at: Time.current, closed_by: user) }

  it "allocates one registry identifier and snapshots the finalized invoice" do
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, amount: 100)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 100)

    expect {
      @invoice = described_class.call!(folio:, issued_by: user, balance: 0)
    }.to change(Invoice, :count).by(1)
      .and change(InvoiceRevision, :count).by(1)

    invoice = @invoice
    expect(invoice).to be_finalized
    expect(invoice.invoice_reference).to eq(folio.reload.invoice_reference)
    expect(invoice.current_revision.document_reference).to eq(invoice.invoice_reference)
    expect(invoice.current_revision.snapshot).to include(
      "folio" => include("id" => folio.id, "currency" => "MYR"),
      "totals" => include("charges" => "100.0", "payments" => "100.0", "balance" => "0.0")
    )
  end

  it "keeps the base identifier and appends a revision suffix after correction" do
    invoice = described_class.call!(folio:, issued_by: user, balance: 0)
    base_reference = invoice.invoice_reference
    invoice.update!(state: "under_correction")

    revised = described_class.call!(folio:, issued_by: user, balance: 0)

    expect(revised.reload.current_revision_number).to eq(2)
    expect(revised.invoice_reference).to eq(base_reference)
    expect(revised.current_revision.document_reference).to eq("#{base_reference}-2")
    expect(revised.revisions.pluck(:revision_number)).to eq([ 1, 2 ])
  end

  it "rejects a folio backed by an AR invoice" do
    relationship = create(:hotel_corporate_account, :direct_bill, hotel: booking.hotel)
    company_folio = create(:booking_folio, :secondary, booking:, hotel: booking.hotel,
      hotel_corporate_account: relationship, status: "closed")
    create(:ar_invoice, booking_folio: company_folio, hotel: booking.hotel, hotel_corporate_account: relationship)

    expect {
      described_class.call!(folio: company_folio, issued_by: user, balance: 0)
    }.to raise_error(ArgumentError, /AR invoice/)
  end

  # The suite runs with transactional fixtures, so a second thread would not see
  # this example's data. These simulate the race the way the folio specs already
  # do: force the allocator into the losing state, then assert the safety net.
  describe "concurrent identifier allocation" do
    let(:second_folio) do
      create(:booking_folio, :secondary, booking:, hotel: booking.hotel,
        status: "closed", closed_at: Time.current, closed_by: user)
    end

    it "issues distinct identifiers to folios closed in the same hotel and year" do
      first = described_class.call!(folio:, issued_by: user, balance: 0)
      second = described_class.call!(folio: second_folio, issued_by: user, balance: 0)

      expect(second.invoice_number).not_to eq(first.invoice_number)
      expect(second.invoice_reference).not_to eq(first.invoice_reference)
      expect(second.invoice_year).to eq(first.invoice_year)
    end

    it "does not reissue a number when the counter lags behind existing folios" do
      first = described_class.call!(folio:, issued_by: user, balance: 0)

      # A restore, snapshot load, or demo reseed can leave the counter behind the
      # real max. Issuer#floor is what stops the next allocation colliding.
      HotelCounter.find_by(
        hotel: booking.hotel,
        counter_type: "invoice",
        sequence_year: first.invoice_year
      ).update_columns(last_value: 0)

      second = described_class.call!(folio: second_folio, issued_by: user, balance: 0)

      expect(second.invoice_number).to be > first.invoice_number
    end

    it "retries and still allocates a distinct number when the counter row races on create" do
      first = described_class.call!(folio:, issued_by: user, balance: 0)

      attempts = 0
      original = HotelCounter.method(:find_or_create_by!)
      allow(HotelCounter).to receive(:find_or_create_by!) do |*args, **kwargs|
        attempts += 1
        raise ActiveRecord::RecordNotUnique, "duplicate key value violates unique constraint" if attempts == 1

        original.call(*args, **kwargs)
      end

      second = described_class.call!(folio: second_folio, issued_by: user, balance: 0)

      expect(attempts).to be >= 2
      expect(second.invoice_number).not_to eq(first.invoice_number)
    end

    it "rejects a duplicate invoice number for the same hotel and year at the database" do
      first = described_class.call!(folio:, issued_by: user, balance: 0)

      expect {
        second_folio.update_columns(
          invoice_number: first.invoice_number,
          invoice_year: first.invoice_year
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
