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
    allow(ChannelManagers::IngestRevisionJob).to receive(:perform_now).and_return(:acked)
  end

  def revision(id, property_id: "prop_1")
    { "type" => "booking_revision", "id" => id, "attributes" => { "id" => id, "property_id" => property_id } }
  end

  def page_of(revisions, total: revisions.size)
    { "data" => revisions, "meta" => { "total" => total } }
  end

  it "lists this property's booking revisions since the outage, oldest first, never GET /bookings" do
    expect(client).to receive(:get).with("/booking_revisions", hash_including(
      "filter[property_id]" => "prop_1",
      "filter[inserted_at][gte]" => "2026-10-07T20:00:00Z",
      "order[inserted_at]" => "asc",
      "pagination[page]" => 1
    )).and_return(page_of([]))

    result = service.call

    expect(result.success?).to be(true)
    expect(result.replayed_count).to eq(0)
  end

  it "replays every revision, including modifications and cancellations, through the ingest job" do
    allow(client).to receive(:get).and_return(page_of([ revision("rev_new"), revision("rev_cancel") ]))

    result = service.call

    expect(result.replayed_count).to eq(2)
    expect(ChannelManagers::IngestRevisionJob).to have_received(:perform_now).with(hotel.id, "rev_new").ordered
    expect(ChannelManagers::IngestRevisionJob).to have_received(:perform_now).with(hotel.id, "rev_cancel").ordered
  end

  it "ignores revisions that belong to another property" do
    allow(client).to receive(:get).and_return(page_of([ revision("rev_1"), revision("rev_x", property_id: "other") ]))

    service.call

    expect(ChannelManagers::IngestRevisionJob).to have_received(:perform_now).once.with(hotel.id, "rev_1")
  end

  it "walks every page by the total Channex reports, even when a page comes back short" do
    allow(client).to receive(:get).with("/booking_revisions", hash_including("pagination[page]" => 1))
      .and_return(page_of([ revision("rev_1") ], total: described_class::PER_PAGE + 1))
    allow(client).to receive(:get).with("/booking_revisions", hash_including("pagination[page]" => 2))
      .and_return(page_of([ revision("rev_last") ], total: described_class::PER_PAGE + 1))

    result = service.call

    expect(result.replayed_count).to eq(2)
    expect(client).to have_received(:get).twice
  end

  it "does not count a revision that was not acknowledged as replayed" do
    allow(client).to receive(:get).and_return(page_of([ revision("rev_retry"), revision("rev_ok") ]))
    # perform_now hands back the error when retry_on swallows it and queues a retry.
    allow(ChannelManagers::IngestRevisionJob).to receive(:perform_now).with(hotel.id, "rev_retry")
      .and_return(Channex::Client::RetryableRequestError.new("busy"))

    result = service.call

    expect(result.success?).to be(false)
    expect(result.replayed_count).to eq(1)
    expect(result.message).to include("rev_retry", "not acknowledged")
  end

  it "reports per-revision failures but keeps going" do
    allow(client).to receive(:get).and_return(page_of([ revision("rev_bad"), revision("rev_ok") ]))
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
    expect(result.message).to include("Failed to list booking revisions")
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
