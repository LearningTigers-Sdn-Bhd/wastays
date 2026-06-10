# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::CloseForCheckout do
  around { |example| travel_to(Time.zone.local(2026, 6, 10, 3, 0, 0)) { example.run } }

  let(:booking) { create(:booking, status: "checked_in", currency: "MYR") }
  let(:user) { create(:user) }

  it "closes the folio when the balance is zero" do
    folio = create(:booking_folio, booking: booking, status: "open")
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 100.0)

    expect {
      @result = described_class.call(booking: booking, user: user)
    }.to change(FinancialAuditEvent, :count).by(1)

    result = @result

    expect(result.success?).to be(true)
    expect(result.folio).to eq(folio)
    expect(result.balance).to eq(0.to_d)
    expect(folio.reload.status).to eq("closed")

    event = FinancialAuditEvent.last
    expect(event.event_type).to eq("folio_closed_for_checkout")
    expect(event.booking_folio).to eq(folio)
    expect(event.booking).to eq(booking)
    expect(event.metadata["invoice_number"]).to eq(folio.invoice_number)
  end

  it "fails when the booking has no folio" do
    expect {
      @result = described_class.call(booking: booking, user: user)
    }.not_to change(FinancialAuditEvent, :count)

    result = @result

    expect(result.success?).to be(false)
    expect(result.error).to eq("Booking has no folio.")
  end

  it "fails when the folio is already closed" do
    create(:booking_folio, booking: booking, status: "closed")

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be(false)
    expect(result.error).to eq("Folio is already closed.")
  end

  it "fails with a positive outstanding balance" do
    folio = create(:booking_folio, booking: booking, status: "open")
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be(false)
    expect(result.error).to eq("Cannot check out with outstanding balance of MYR 100.00.")
    expect(folio.reload.status).to eq("open")
  end

  it "fails with a negative credit balance" do
    folio = create(:booking_folio, booking: booking, status: "open")
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 50.0)

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be(false)
    expect(result.error).to eq("Cannot check out with credit balance of MYR -50.00. Process refund or adjustment first.")
    expect(folio.reload.status).to eq("open")
  end

  it "fails while the checkout business date is in night audit" do
    folio = create(:booking_folio, booking: booking, status: "open")
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 100.0)
    business_date = booking.hotel.business_date_for
    create(:hotel_business_date, hotel: booking.hotel, business_date: business_date, status: "audit_running")

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be(false)
    expect(result.error).to include("currently in night audit")
    expect(folio.reload.status).to eq("open")
  end

  context "with past nights" do
    let(:check_in) { 2.days.ago.to_date }
    let(:booking) { create(:booking, status: "checked_in", check_in: check_in, check_out: Date.current) }

    it "fails when nightly charges are missing for past nights" do
      folio = create(:booking_folio, booking: booking, status: "open")
      create(:booking_room, booking: booking, subtotal: 200.0)
      # Post one charge but not the other
      create(:folio_transaction,
        booking_folio: folio,
        transaction_type: :charge,
        category: "accommodation",
        amount: 100.0,
        metadata: { stay_date: check_in.iso8601 }
      )

      # The second night (yesterday) is missing

      result = described_class.call(booking: booking, user: user)

      expect(result.success?).to be(false)
      expect(result.error).to include("Missing nightly charges for")
      expect(result.error).to include(1.day.ago.to_date.strftime('%d %b'))
    end

    it "succeeds when all past nights have charges with stay_date metadata" do
      folio = create(:booking_folio, booking: booking, status: "open")
      create(:booking_room, booking: booking, subtotal: 200.0)

      # Night 1
      create(:folio_transaction,
        booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0,
        metadata: { stay_date: check_in.iso8601 }
      )
      # Night 2
      create(:folio_transaction,
        booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0,
        metadata: { stay_date: 1.day.ago.to_date.iso8601 }
      )

      # Settlement
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 200.0)

      result = described_class.call(booking: booking, user: user)
      expect(result.success?).to be(true)
      expect(folio.reload.status).to eq("closed")
    end

    it "fails when accommodation is posted but expected tax is missing" do
      booking.update!(tax_lines: [ { "name" => "SST", "amount" => "20.00", "type" => "sst" } ])
      folio = create(:booking_folio, booking: booking, status: "open")
      create(:booking_room, booking: booking, subtotal: 200.0)

      [ check_in, 1.day.ago.to_date ].each do |stay_date|
        create(:folio_transaction,
          booking_folio: folio,
          transaction_type: :charge,
          category: "accommodation",
          amount: 100.0,
          metadata: { stay_date: stay_date.iso8601 })
      end
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 200.0)

      result = described_class.call(booking: booking, user: user)

      expect(result.success?).to be(false)
      expect(result.error).to include("Missing nightly charges for")
      expect(folio.reload.status).to eq("open")
    end

    it "fails when tax is posted but expected accommodation is missing" do
      booking.update!(tax_lines: [ { "name" => "SST", "amount" => "20.00", "type" => "sst" } ])
      folio = create(:booking_folio, booking: booking, status: "open")
      create(:booking_room, booking: booking, subtotal: 200.0)

      [ check_in, 1.day.ago.to_date ].each do |stay_date|
        create(:folio_transaction,
          booking_folio: folio,
          transaction_type: :charge,
          category: "tax",
          amount: 10.0,
          metadata: { stay_date: stay_date.iso8601 })
      end
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 20.0)

      result = described_class.call(booking: booking, user: user)

      expect(result.success?).to be(false)
      expect(result.error).to include("Missing nightly charges for")
      expect(folio.reload.status).to eq("open")
    end

    it "fails when accommodation is under-posted" do
      folio = create(:booking_folio, booking: booking, status: "open")
      create(:booking_room, booking: booking, subtotal: 200.0)

      [ check_in, 1.day.ago.to_date ].each do |stay_date|
        create(:folio_transaction,
          booking_folio: folio,
          transaction_type: :charge,
          category: "accommodation",
          amount: 99.0,
          metadata: { stay_date: stay_date.iso8601 })
      end
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 198.0)

      result = described_class.call(booking: booking, user: user)

      expect(result.success?).to be(false)
      expect(result.error).to include("Missing nightly charges for")
      expect(folio.reload.status).to eq("open")
    end
  end
end
