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
    booking.hotel.current_business_date_record.update!(status: "audit_running")

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be(false)
    expect(result.error).to include("currently in night audit")
    expect(folio.reload.status).to eq("open")
  end

  it "syncs captured local payments before calculating checkout balance" do
    folio = create(:booking_folio, booking: booking, status: "open")
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)
    payment = create(:payment_transaction, booking: booking, status: "captured", amount_subunits: 10_000, captured_at: Time.current)

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be(true)
    expect(folio.reload.status).to eq("closed")
    expect(folio.folio_transactions.payment.where("metadata->>'payment_transaction_id' = ?", payment.id.to_s)).to exist
  end

  it "keeps the folio open when a captured payment cannot be synced" do
    folio = create(:booking_folio, booking: booking, status: "open")
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)
    create(:payment_transaction, booking: booking, status: "captured", amount_subunits: 10_000, captured_at: Time.current)
    allow(Folios::RecordPaymentFromGateway).to receive(:call).and_return(Folios::TransactionResult.failure("sync failed"))

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be(false)
    expect(result.error).to eq("Cannot check out: captured payment is not synced to the folio.")
    expect(folio.reload.status).to eq("open")
  end

  it "syncs completed local refunds before recalculating checkout balance" do
    folio = create(:booking_folio, booking: booking, status: "open")
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 100.0)
    refund = create(:refund_request, booking: booking, status: "completed", refund_amount: 20.0)

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be(false)
    expect(result.error).to eq("Cannot check out with outstanding balance of MYR 20.00.")
    expect(folio.reload.status).to eq("open")
    expect(folio.folio_transactions.payment.where("metadata->>'refund_request_id' = ?", refund.id.to_s)).to exist
  end

  it "keeps the folio open when a completed refund cannot be synced" do
    folio = create(:booking_folio, booking: booking, status: "open")
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 100.0)
    create(:refund_request, booking: booking, status: "completed", refund_amount: 20.0)
    allow(Folios::RecordRefund).to receive(:call).and_return(Folios::TransactionResult.failure("sync failed"))

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be(false)
    expect(result.error).to eq("Cannot check out: completed refund is not synced to the folio.")
    expect(folio.reload.status).to eq("open")
  end

  context "with past nights" do
    let(:check_in) { 2.days.ago.to_date }
    let(:booking) { create(:booking, status: "checked_in", check_in: check_in, check_out: Date.current) }
    let(:folio) { create(:booking_folio, booking: booking, status: "open") }

    before do
      create(:booking_room, booking: booking, subtotal: 200.0)
      Folios::SyncForecastedCharges.call(booking_folio: folio)
    end

    it "fails when nightly charges are missing for past nights" do
      # Post one charge but not the other
      result = described_class.call(booking: booking, user: user)

      expect(result.success?).to be(false)
      expect(result.error).to include("Missing nightly charges for")
      expect(result.error).to include(1.day.ago.to_date.strftime('%d %b'))
      expect(result.error).to include(check_in.strftime('%d %b'))
    end

    it "does not fail for a forecast when a matching nightly charge exists on another booking folio" do
      company_folio = create(:booking_folio, :secondary, booking: booking, hotel: booking.hotel)
      forecast = folio.folio_forecasted_charges.forecast.order(:stay_date).first
      key = Folios::ChargePostingKeys.nightly_charge_key(booking: booking, date: forecast.stay_date, charge_kind: forecast.charge_kind, identity: forecast.identity)
      create(:folio_transaction,
        booking_folio: company_folio,
        transaction_type: :charge,
        category: "accommodation",
        amount: forecast.amount,
        metadata: { nightly_charge_key: key })
      forecast.update!(status: "forecast")

      result = described_class.call(booking: booking, user: user)

      expect(result.success?).to be(false)
      expect(result.error).to include("Missing nightly charges for")
      expect(result.error).not_to include(forecast.stay_date.strftime("%d %b"))
    end

    it "does not fail for a forecast when a matching catch-up charge exists on another booking folio" do
      company_folio = create(:booking_folio, :secondary, booking: booking, hotel: booking.hotel)
      forecast = folio.folio_forecasted_charges.forecast.order(:stay_date).first
      key = Folios::ChargePostingKeys.catch_up_charge_key(booking: booking, date: forecast.stay_date, charge_kind: forecast.charge_kind, identity: forecast.identity)
      create(:folio_transaction,
        booking_folio: company_folio,
        transaction_type: :charge,
        category: "accommodation",
        amount: forecast.amount,
        catch_up_key: key,
        metadata: { catch_up_key: key })
      forecast.update!(status: "forecast")

      result = described_class.call(booking: booking, user: user)

      expect(result.success?).to be(false)
      expect(result.error).to include("Missing nightly charges for")
      expect(result.error).not_to include(forecast.stay_date.strftime("%d %b"))
    end

    it "syncs forecasts before validation so legacy open folios cannot bypass missing-charge checks" do
      folio.folio_forecasted_charges.destroy_all

      result = described_class.call(booking: booking, user: user)

      expect(result.success?).to be(false)
      expect(result.error).to include("Missing nightly charges for")
      expect(folio.folio_forecasted_charges.forecast.count).to eq(2)
    end

    it "succeeds when all past nights have charges" do
      # Actualize both forecast charges
      folio.folio_forecasted_charges.forecast.each do |forecast|
        txn = create(:folio_transaction,
          booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: forecast.amount,
          metadata: { stay_date: forecast.stay_date.iso8601 })
        forecast.actualize!(transaction: txn)
      end

      # Settlement
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 200.0)

      result = described_class.call(booking: booking, user: user)
      expect(result.success?).to be(true)
      expect(folio.reload.status).to eq("closed")
    end

    it "fails when accommodation is posted but expected tax is missing" do
      booking.update!(tax_lines: [ { "name" => "SST", "amount" => "20.00", "type" => "sst" } ])
      # Regenerate forecasts with tax lines
      folio.folio_forecasted_charges.supersede_all!
      Folios::SyncForecastedCharges.call(booking_folio: folio)

      # Actualize only accommodation forecasts
      folio.folio_forecasted_charges.forecast.where(charge_kind: "accommodation").each do |forecast|
        txn = create(:folio_transaction,
          booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: forecast.amount,
          metadata: { stay_date: forecast.stay_date.iso8601 })
        forecast.actualize!(transaction: txn)
      end
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 200.0)

      result = described_class.call(booking: booking, user: user)

      expect(result.success?).to be(false)
      expect(result.error).to include("Missing nightly charges for")
      expect(folio.reload.status).to eq("open")
    end

    it "fails when tax is posted but expected accommodation is missing" do
      booking.update!(tax_lines: [ { "name" => "SST", "amount" => "20.00", "type" => "sst" } ])
      folio.folio_forecasted_charges.supersede_all!
      Folios::SyncForecastedCharges.call(booking_folio: folio)

      # Actualize only tax forecasts
      folio.folio_forecasted_charges.forecast.where(charge_kind: "tax").each do |forecast|
        txn = create(:folio_transaction,
          booking_folio: folio, transaction_type: :charge, category: "tax", amount: forecast.amount,
          metadata: { stay_date: forecast.stay_date.iso8601 })
        forecast.actualize!(transaction: txn)
      end
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 20.0)

      result = described_class.call(booking: booking, user: user)

      expect(result.success?).to be(false)
      expect(result.error).to include("Missing nightly charges for")
      expect(folio.reload.status).to eq("open")
    end

    it "fails when accommodation is under-posted (forecast still exists)" do
      # Actualize one accommodation but leave the other (night 2) as forecast
      first_forecast = folio.folio_forecasted_charges.forecast.where(charge_kind: "accommodation").order(:stay_date).first
      txn = create(:folio_transaction,
        booking_folio: folio, transaction_type: :charge, category: "accommodation",
        amount: first_forecast.amount,
        metadata: { stay_date: first_forecast.stay_date.iso8601 })
      first_forecast.actualize!(transaction: txn)

      # The second night remains un-actualized
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 100.0)

      result = described_class.call(booking: booking, user: user)

      expect(result.success?).to be(false)
      expect(result.error).to include("Missing nightly charges for")
      expect(folio.reload.status).to eq("open")
    end
  end
end
