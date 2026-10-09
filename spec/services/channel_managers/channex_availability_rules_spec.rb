# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::ChannexAvailabilityRules do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:agoda) { "agoda-channel-uuid" }
  let(:client) { instance_double(Channex::Client, delete: { "meta" => {} }) }
  let(:posted) { [] }

  before do
    allow(client).to receive(:post) do |_, body|
      posted << body[:channel_availability_rule]
      { "data" => {} }
    end
  end

  def sync(date_range)
    described_class.new(client: client, property_id: "prop-1", external_room_type_ids: { room_type.id => "ch-rt-1" }).call(date_range)
  end

  def close_agoda(dates)
    dates.each do |date|
      ChannelRoomRate.create!(room_type: room_type, channel_id: agoda, date: date, stop_sell: true)
    end
  end

  def rule(id, from, to, channel: agoda)
    {
      "id" => id,
      "attributes" => {
        "title" => "PMS Override", "type" => "close_out",
        "start_date" => from.to_s, "end_date" => to.to_s,
        "affected_channels" => [ channel ], "affected_room_types" => [ "ch-rt-1" ]
      }
    }
  end

  def list(*rules, total: rules.size)
    { "data" => rules, "meta" => { "total" => total, "page" => 1, "limit" => 100 } }
  end

  def created_rules
    posted.map { |r| r.slice(:type, :start_date, :end_date, :affected_channels) }
  end

  it "keeps a month-long close-out whole when a single night is pushed" do
    november = Date.new(2026, 11, 1)..Date.new(2026, 11, 30)
    close_agoda(november)
    allow(client).to receive(:get).and_return(list(rule("r1", november.first, november.last)))

    sync(Date.new(2026, 11, 10)..Date.new(2026, 11, 10))

    expect(client).to have_received(:delete).with("/channel_availability_rules/r1")
    expect(created_rules).to eq([
      { type: "close_out", start_date: "2026-11-01", end_date: "2026-11-30", affected_channels: [ agoda ] }
    ])
  end

  it "reads every page of rules so older ones are still found" do
    close_agoda([ Date.new(2026, 11, 10) ])
    allow(client).to receive(:get).with("/channel_availability_rules", hash_including("pagination" => { "page" => 1, "limit" => 100 }))
      .and_return(list(*Array.new(100) { |i| rule("new-#{i}", Date.new(2027, 1, 1), Date.new(2027, 1, 2)) }, total: 101))
    allow(client).to receive(:get).with("/channel_availability_rules", hash_including("pagination" => { "page" => 2, "limit" => 100 }))
      .and_return(list(rule("old", Date.new(2026, 11, 9), Date.new(2026, 11, 11)), total: 101))

    sync(Date.new(2026, 11, 10)..Date.new(2026, 11, 10))

    expect(client).to have_received(:delete).with("/channel_availability_rules/old")
  end

  it "clears a rule whose override is gone" do
    ChannelRoomRate.create!(room_type: room_type, channel_id: "other-channel", date: Date.new(2026, 12, 1), stop_sell: true)
    allow(client).to receive(:get).and_return(list(rule("stale", Date.new(2026, 11, 9), Date.new(2026, 11, 11))))

    sync(Date.new(2026, 11, 10)..Date.new(2026, 11, 10))

    expect(client).to have_received(:delete).with("/channel_availability_rules/stale")
    expect(client).not_to have_received(:post)
  end

  it "leaves alone a rule the hotel made by hand on the dashboard" do
    ChannelRoomRate.create!(room_type: room_type, channel_id: "other-channel", date: Date.new(2026, 12, 1), stop_sell: true)
    allow(client).to receive(:get).and_return(list(rule("hand-made", Date.new(2026, 11, 9), Date.new(2026, 11, 11))))

    described_class.new(
      client: client, property_id: "prop-1", external_room_type_ids: { room_type.id => "ch-rt-1" }, owned_rule_ids: [ "hand-made" ]
    ).call(Date.new(2026, 11, 10)..Date.new(2026, 11, 10))

    expect(client).not_to have_received(:delete)
  end

  it "makes no calls for a hotel that never set a per-OTA override" do
    allow(client).to receive(:get)

    sync(Date.new(2026, 11, 10)..Date.new(2026, 11, 10))

    expect(client).not_to have_received(:get)
  end

  it "raises on a retryable failure so the push retries" do
    close_agoda([ Date.new(2026, 11, 10) ])
    allow(client).to receive(:get).and_return(list)
    allow(client).to receive(:post).and_return({ error: "Channel Manager API error: 429", retryable: true })

    expect { sync(Date.new(2026, 11, 10)..Date.new(2026, 11, 10)) }
      .to raise_error(Channex::Client::RetryableRequestError, /create close_out rule/)
  end

  it "touches nothing when the rule list can't be read" do
    close_agoda([ Date.new(2026, 11, 10) ])
    allow(client).to receive(:get).and_return({ error: "Channel Manager API error: 401", retryable: false })

    sync(Date.new(2026, 11, 10)..Date.new(2026, 11, 10))

    expect(client).not_to have_received(:delete)
    expect(client).not_to have_received(:post)
  end
end
