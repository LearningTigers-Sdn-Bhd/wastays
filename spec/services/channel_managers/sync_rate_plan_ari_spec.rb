# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::SyncRatePlanAri do
  include ActiveJob::TestHelper

  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
  let(:rate_plan) { create(:rate_plan, hotel: hotel, name: "Breakfast Rate", kind: "custom") }

  def link(room_type)
    create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan, pricing_mode: "fixed")
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    Thread.current[:skip_ari_sync] = true
  end

  after { Thread.current[:skip_ari_sync] = nil }

  it "pushes one rate sync covering every room category, not one per category" do
    room_types = Array.new(3) { |i| create(:room_type, hotel: hotel, name: "Villa #{i}") }
    room_types.each { |rt| link(rt) }
    clear_enqueued_jobs

    described_class.call(rate_plan: rate_plan, room_type_ids: room_types.map(&:id))

    rate_syncs = enqueued_jobs.select { |job| job[:job] == ChannelManagers::SyncJob }
    expect(rate_syncs.size).to eq(1)
    expect(rate_syncs.first[:args].last["room_type_ids"]).to match_array(room_types.map(&:id))
    expect(rate_syncs.first[:args].last["rate_plan_ids"]).to eq([ rate_plan.id ])
  end

  it "still enqueues one structure sync per mapping, which the channel manager needs" do
    room_types = Array.new(3) { |i| create(:room_type, hotel: hotel, name: "Villa #{i}") }
    room_types.each { |rt| link(rt) }
    clear_enqueued_jobs

    described_class.call(rate_plan: rate_plan, room_type_ids: room_types.map(&:id))

    structure_syncs = enqueued_jobs.select { |job| job[:job] == ChannelManagers::SyncStructureJob }
    expect(structure_syncs.size).to eq(3)
  end

  it "does nothing when the hotel has no channel manager connected" do
    hotel.update!(preferred_channel_manager: nil)
    room_type = create(:room_type, hotel: hotel)
    link(room_type)
    clear_enqueued_jobs

    described_class.call(rate_plan: rate_plan, room_type_ids: [ room_type.id ])

    expect(enqueued_jobs).to be_empty
  end

  it "does nothing when no room categories are assigned" do
    rate_plan # RatePlan has its own after_commit sync; create it before clearing
    clear_enqueued_jobs

    described_class.call(rate_plan: rate_plan, room_type_ids: [])

    expect(enqueued_jobs).to be_empty
  end

  it "does not enqueue unsupported per-person channel pushes" do
    hotel.update!(sell_mode: "per_person")
    room_type = create(:room_type, hotel: hotel)
    link(room_type)
    clear_enqueued_jobs

    described_class.call(rate_plan: rate_plan, room_type_ids: [ room_type.id ])

    expect(enqueued_jobs).to be_empty
  end
end
