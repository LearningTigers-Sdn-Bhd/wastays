# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::FetchBookingsService do
  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
  let!(:mapping) { create(:channel_mapping, provider: "channex", mappable: hotel, external_id: "external_prop_123") }
  let(:service) { described_class.new(hotel: hotel) }
  let(:client) { instance_double(Channex::Client) }
  let(:adapter) { instance_double(ChannelManagers::ChannexAdapter) }

  before do
    allow(Channex::Client).to receive(:new).and_return(client)
    allow(ChannelManagers::SyncOrchestrator).to receive(:adapter_for).with(hotel).and_return(adapter)
  end

  it "returns failure if channel manager not selected" do
    hotel.update(preferred_channel_manager: nil)
    result = service.call
    expect(result.success?).to be(false)
    expect(result.message).to eq("Channel manager not selected")
  end

  it "successfully fetches and ingests bookings" do
    response_data = {
      "data" => [
        { "id" => "booking_1" },
        { "id" => "booking_2" }
      ]
    }
    allow(client).to receive(:get).with("/bookings", { "filter[property_id]" => "external_prop_123" }).and_return(response_data)

    booking_data_1 = { channel_manager_reference: "REF1" }
    booking_data_2 = { channel_manager_reference: "REF2" }

    allow(adapter).to receive(:ingest_booking).with(payload: response_data["data"][0]).and_return(booking_data_1)
    allow(adapter).to receive(:ingest_booking).with(payload: response_data["data"][1]).and_return(booking_data_2)

    ingest_result = double(success?: true)
    allow(ChannelManagers::IngestBookingService).to receive(:new).and_return(double(call: ingest_result))

    result = service.call

    expect(result.success?).to be(true)
    expect(result.ingested_count).to eq(2)
  end

  it "handles partial failures during ingestion" do
    response_data = {
      "data" => [
        { "id" => "booking_1" }
      ]
    }
    allow(client).to receive(:get).and_return(response_data)
    allow(adapter).to receive(:ingest_booking).and_return({ channel_manager_reference: "REF1" })

    ingest_result = double(success?: false, message: "Validation error")
    allow(ChannelManagers::IngestBookingService).to receive(:new).and_return(double(call: ingest_result))

    result = service.call

    expect(result.success?).to be(true)
    expect(result.ingested_count).to eq(0)
    expect(result.message).to include("Sync partially successful")
  end
end
