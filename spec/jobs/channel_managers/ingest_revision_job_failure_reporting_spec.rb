# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe ChannelManagers::IngestRevisionJob, "failure reporting", type: :job do
  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
  let(:client) { instance_double(Channex::Client) }
  let(:adapter) { instance_double(ChannelManagers::ChannexAdapter, ingest_booking: { settlement: nil }) }

  before do
    allow(Channex::Client).to receive(:new).and_return(client)
    allow(ChannelManagers::SyncOrchestrator).to receive(:adapter_for).and_return(adapter)
    allow(client).to receive(:get).with("/booking_revisions/rev_1").and_return({ "data" => { "id" => "rev_1" } })
  end

  def stub_ingest(result)
    allow(ChannelManagers::IngestBookingService).to receive(:new).and_return(instance_double(ChannelManagers::IngestBookingService, call: result))
  end

  it "reports an ingestion failure that has no failure code, and leaves the revision unacked" do
    stub_ingest(OpenStruct.new(success?: false, message: "Missing mandatory dates", failure_code: nil))
    expect(client).not_to receive(:post)

    expect(Rails.error).to receive(:report).with(
      an_instance_of(ChannelManagers::IngestBookingService::UnprocessableBooking),
      hash_including(handled: true, severity: :error, context: hash_including(hotel_id: hotel.id, revision_id: "rev_1"))
    )

    described_class.perform_now(hotel.id, "rev_1")
  end

  it "reports a non-retryable ack failure" do
    stub_ingest(OpenStruct.new(success?: true, booking: nil, bookings: nil))
    allow(client).to receive(:post).with("/booking_revisions/rev_1/ack").and_return({ error: "nope", retryable: false })

    expect(Rails.error).to receive(:report).with(
      an_instance_of(ChannelManagers::IngestBookingService::UnprocessableBooking),
      hash_including(context: hash_including(revision_id: "rev_1"))
    )

    described_class.perform_now(hotel.id, "rev_1")
  end

  it "does not report a successful ingest" do
    stub_ingest(OpenStruct.new(success?: true, booking: nil, bookings: nil))
    allow(client).to receive(:post).with("/booking_revisions/rev_1/ack").and_return({ "meta" => { "message" => "Success" } })

    expect(Rails.error).not_to receive(:report)

    described_class.perform_now(hotel.id, "rev_1")
  end
end
