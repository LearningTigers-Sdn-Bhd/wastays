require "rails_helper"

RSpec.describe PayoutEngine::GenerateWeeklyBatches do
  before do
    allow_any_instance_of(described_class).to receive(:puts)
  end

  it "creates one payout batch per hotel for eligible bookings" do
    hotel = create(:hotel)
    create(:e_invoice_setting, :intermediary_ready, hotel: hotel)
    create(:booking, hotel: hotel, booking_quote: create(:booking_quote, hotel: hotel), fund_collector: "wastays", status: "completed", checked_out_at: Date.new(2026, 4, 17).end_of_day, net_amount: 120.0, payout_batch_id: nil)
    create(:booking, hotel: hotel, booking_quote: create(:booking_quote, hotel: hotel), fund_collector: "wastays", status: "completed", checked_out_at: Date.new(2026, 4, 16).end_of_day, net_amount: 80.0, payout_batch_id: nil)

    allow(Date).to receive(:current).and_return(Date.new(2026, 4, 18))

    expect {
      described_class.call
    }.to change(PayoutBatch, :count).by(1)

    batch = PayoutBatch.last
    expect(batch.amount.to_f).to eq(200.0)
    expect(batch.status).to eq("pending")
    expect(Booking.where(payout_batch_id: batch.id).count).to eq(2)
    expect(EInvoiceSubmission.payout_self_billed.where(payout_batch: batch).count).to eq(2)
  end

  it "does nothing when there are no eligible completed bookings" do
    allow(Date).to receive(:current).and_return(Date.new(2026, 4, 18))

    expect {
      described_class.call
    }.not_to change(PayoutBatch, :count)
  end

  it "creates separate batches per hotel" do
    hotel_a = create(:hotel)
    hotel_b = create(:hotel)
    create(:e_invoice_setting, :intermediary_ready, hotel: hotel_a)
    create(:e_invoice_setting, :intermediary_ready, hotel: hotel_b)
    create(:booking, hotel: hotel_a, booking_quote: create(:booking_quote, hotel: hotel_a), fund_collector: "wastays", status: "completed", checked_out_at: Date.new(2026, 4, 17).end_of_day, net_amount: 100.0, payout_batch_id: nil)
    create(:booking, hotel: hotel_b, booking_quote: create(:booking_quote, hotel: hotel_b), fund_collector: "wastays", status: "completed", checked_out_at: Date.new(2026, 4, 17).end_of_day, net_amount: 50.0, payout_batch_id: nil)

    allow(Date).to receive(:current).and_return(Date.new(2026, 4, 18))

    expect {
      described_class.call
    }.to change(PayoutBatch, :count).by(2)

    amounts = PayoutBatch.order(:id).last(2).map { |b| b.amount.to_f }
    expect(amounts).to match_array([ 100.0, 50.0 ])
  end

  it "skips direct-hotel bookings from payout batches" do
    hotel = create(:hotel)
    create(:booking, :direct_hotel_payment, hotel: hotel, status: "completed", checked_out_at: Date.new(2026, 4, 17).end_of_day, net_amount: 120.0, payout_batch_id: nil)

    allow(Date).to receive(:current).and_return(Date.new(2026, 4, 18))

    expect {
      described_class.call
    }.not_to change(PayoutBatch, :count)
  end
end
