# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::FetchBookingsService do
  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
  let!(:mapping) { create(:channel_mapping, provider: "channex", mappable: hotel, external_id: "external_prop_123") }
  let(:service) { described_class.new(hotel: hotel) }
  let(:client) { instance_double(Channex::Client) }

  before do
    allow(Channex::Client).to receive(:new).and_return(client)
  end

  it "returns failure if channel manager not selected" do
    hotel.update(preferred_channel_manager: nil)
    result = service.call
    expect(result.success?).to be(false)
    expect(result.message).to eq("Channel manager not selected")
  end

  it "successfully fetches and ingests booking revisions for the mapped property" do
    response_data = {
      "data" => [
        { "id" => "rev_1", "property_id" => "external_prop_123" },
        { "id" => "rev_2", "property_id" => "external_prop_123" },
        { "id" => "rev_3", "property_id" => "another_property" }
      ],
      "meta" => { "pagination" => { "current_page" => 1, "total_pages" => 1 } }
    }
    allow(client).to receive(:get).with("/booking_revisions/feed", hash_including("order[inserted_at]" => "asc")).and_return(response_data)
    allow(ChannelManagers::IngestRevisionJob).to receive(:perform_now)

    result = service.call

    expect(result.success?).to be(true)
    expect(result.ingested_count).to eq(2)
    expect(ChannelManagers::IngestRevisionJob).to have_received(:perform_now).with(hotel.id, "rev_1")
    expect(ChannelManagers::IngestRevisionJob).to have_received(:perform_now).with(hotel.id, "rev_2")
  end

  it "handles partial failures during ingestion" do
    response_data = {
      "data" => [
        { "id" => "rev_1", "property_id" => "external_prop_123" }
      ],
      "meta" => { "pagination" => { "current_page" => 1, "total_pages" => 1 } }
    }
    allow(client).to receive(:get).with("/booking_revisions/feed", hash_including("order[inserted_at]" => "asc")).and_return(response_data)
    allow(ChannelManagers::IngestRevisionJob).to receive(:perform_now).and_raise("Validation error")

    result = service.call

    expect(result.success?).to be(true)
    expect(result.ingested_count).to eq(0)
    expect(result.message).to include("Sync partially successful")
  end
end
