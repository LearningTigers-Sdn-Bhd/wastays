# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::RecoverBookingsService do
  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
  let!(:mapping) { create(:channel_mapping, provider: "channex", mappable: hotel, external_id: "prop_1") }
  let(:since) { Time.utc(2026, 10, 7, 20, 0, 0) }
  let(:client) { instance_double(Channex::Client) }
  let(:service) { described_class.new(hotel: hotel, since: since) }

  before do
    allow(Channex::Client).to receive(:new).and_return(client)
    allow(ChannelManagers::IngestRevisionJob).to receive(:perform_now)
  end

  def booking(revision_id, property_id: "prop_1")
    { "type" => "booking", "id" => "b_#{revision_id}", "attributes" => { "property_id" => property_id, "revision_id" => revision_id } }
  end

  it "asks Channex only for this property's bookings since the outage" do
    expect(client).to receive(:get).with("/bookings", hash_including(
      "filter[property_id]" => "prop_1",
      "filter[inserted_at][gte]" => "2026-10-07T20:00:00Z",
      "pagination[page]" => 1
    )).and_return({ "data" => [] })

    result = service.call

    expect(result.success?).to be(true)
    expect(result.replayed_count).to eq(0)
  end

  it "replays each booking's latest revision through the ingest job" do
    allow(client).to receive(:get).and_return({ "data" => [ booking("rev_1"), booking("rev_2") ] })

    result = service.call

    expect(result.replayed_count).to eq(2)
    expect(ChannelManagers::IngestRevisionJob).to have_received(:perform_now).with(hotel.id, "rev_1")
    expect(ChannelManagers::IngestRevisionJob).to have_received(:perform_now).with(hotel.id, "rev_2")
  end

  it "ignores bookings that belong to another property" do
    allow(client).to receive(:get).and_return({ "data" => [ booking("rev_1"), booking("rev_x", property_id: "other") ] })

    service.call

    expect(ChannelManagers::IngestRevisionJob).to have_received(:perform_now).once.with(hotel.id, "rev_1")
  end

  it "walks every page" do
    full_page = Array.new(described_class::PER_PAGE) { |i| booking("rev_#{i}") }
    allow(client).to receive(:get).with("/bookings", hash_including("pagination[page]" => 1)).and_return({ "data" => full_page })
    allow(client).to receive(:get).with("/bookings", hash_including("pagination[page]" => 2)).and_return({ "data" => [ booking("rev_last") ] })

    result = service.call

    expect(result.replayed_count).to eq(described_class::PER_PAGE + 1)
  end

  it "reports per-revision failures but keeps going" do
    allow(client).to receive(:get).and_return({ "data" => [ booking("rev_bad"), booking("rev_ok") ] })
    allow(ChannelManagers::IngestRevisionJob).to receive(:perform_now).with(hotel.id, "rev_bad").and_raise("boom")

    result = service.call

    expect(result.success?).to be(false)
    expect(result.replayed_count).to eq(1)
    expect(result.message).to include("rev_bad", "boom")
  end

  it "fails when Channex returns an error" do
    allow(client).to receive(:get).and_return({ error: "Channel Manager API error: 500", details: "down" })

    result = service.call

    expect(result.success?).to be(false)
    expect(result.message).to include("Failed to list bookings")
  end

  it "refuses a hotel with no channel manager" do
    hotel.update!(preferred_channel_manager: "undecided")

    expect(service.call.message).to eq("Channel manager not selected")
  end

  it "refuses a hotel whose Channex property was never created" do
    mapping.update!(external_id: "pending_1")

    expect(service.call.message).to eq("Hotel has no Channex property yet")
  end
end
