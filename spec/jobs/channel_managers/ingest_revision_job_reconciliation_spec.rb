# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::IngestRevisionJob, type: :job do
  include ActiveJob::TestHelper

  it "acknowledges the booking and queues a durable settlement retry" do
    hotel = create(:hotel, preferred_channel_manager: "channex")
    client = instance_double(Channex::Client)
    adapter = double
    settlement_data = {
      provider: "channex",
      booking_source_key: nil,
      channel_manager_reference: "channel-1",
      collection_by: "ota"
    }
    booking = create(:booking, hotel: hotel, channel_manager_reference: "channel-1")
    ingestion = double(success?: true, booking: booking)
    persistence = double(success?: false, settlement: nil, message: "OTA source is unresolved")

    allow(Channex::Client).to receive(:new).and_return(client)
    allow(client).to receive(:get).with("/booking_revisions/revision-1").and_return("data" => { "id" => "channel-1" })
    allow(client).to receive(:post).with("/booking_revisions/revision-1/ack").and_return("meta" => { "message" => "Success" })
    allow(ChannelManagers::SyncOrchestrator).to receive(:adapter_for).with(hotel).and_return(adapter)
    allow(adapter).to receive(:ingest_booking).and_return(hotel: hotel, settlement: settlement_data)
    allow(ChannelManagers::IngestBookingService).to receive(:new).and_return(double(call: ingestion))
    allow(ChannelManagers::PersistSettlement).to receive(:new).and_return(double(call: persistence))

    expect {
      described_class.perform_now(hotel.id, "revision-1")
    }.to have_enqueued_job(ChannelManagers::ReconcileSettlementJob).with(hotel.id, settlement_data)
  end
end
