require "rails_helper"

RSpec.describe NightAudits::Evaluation::Context do
  let(:hotel) { create(:hotel) }
  let(:business_date) { Date.current - 1.day }

  it "normalizes its date and phase" do
    context = described_class.new(hotel: hotel, business_date: business_date.to_time, phase: "pre_close")

    expect(context.business_date).to eq(business_date)
    expect(context.phase).to eq(:pre_close)
    expect(context).to be_pre_close
    expect(context).not_to be_post_close
  end

  it "rejects unsupported and missing phases" do
    expect do
      described_class.new(hotel: hotel, business_date: business_date, phase: :invalid)
    end.to raise_error(ArgumentError, /invalid/)

    expect do
      described_class.new(hotel: hotel, business_date: business_date, phase: nil)
    end.to raise_error(ArgumentError, /nil/)
  end

  it "loads and memoizes the shared booking query results" do
    relevant = [ instance_double(Booking) ]
    nightly = [ instance_double(Booking) ]

    allow(NightAudits::FinanciallyRelevantBookings).to receive(:call).and_return(relevant)
    allow(NightAudits::NightlyChargeCandidates).to receive(:call).and_return(nightly)

    context = described_class.new(hotel: hotel, business_date: business_date, phase: :post_close)

    expect(context.financially_relevant_bookings).to equal(relevant)
    expect(context.financially_relevant_bookings).to equal(relevant)
    expect(context.nightly_charge_candidates).to equal(nightly)
    expect(context.nightly_charge_candidates).to equal(nightly)
    expect(NightAudits::FinanciallyRelevantBookings).to have_received(:call).once
    expect(NightAudits::NightlyChargeCandidates).to have_received(:call).once
  end
end
