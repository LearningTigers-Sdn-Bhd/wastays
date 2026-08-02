require "rails_helper"

RSpec.describe NightAudits::Evaluation::Checks::MissedArrivals do
  it "serializes overdue guest stays as unresolved missed arrivals" do
    context = instance_double(NightAudits::Evaluation::Context)
    serializer = instance_double(NightAudits::Evaluation::SerializeItems)
    stays = instance_double(NightAudits::Evaluation::OverdueGuestStays)
    bookings = [ instance_double(Booking) ]
    serialized = [ { "booking_id" => 123 } ]

    allow(NightAudits::Evaluation::OverdueGuestStays).to receive(:new).with(context: context).and_return(stays)
    allow(stays).to receive(:missed_arrivals).and_return(bookings)
    allow(serializer).to receive(:bookings)
      .with(bookings, described_class::REASON)
      .and_return(serialized)

    result = described_class.new(context: context, serializer: serializer).call

    expect(result).to eq("missed_arrival_not_resolved" => serialized)
  end

  it "is registered for every evaluation phase" do
    expect(NightAudits::Evaluate::PRE_CLOSE_CHECKS).to include(described_class)
    expect(NightAudits::Evaluate::POST_CLOSE_CHECKS).to include(described_class)
  end
end
