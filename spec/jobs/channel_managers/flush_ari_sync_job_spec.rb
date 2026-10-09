# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::FlushAriSyncJob, type: :job do
  include ActiveJob::TestHelper

  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache_store)
    Rails.cache.clear
  end

  it 'flushes buffered window via sync job and clears cache keys' do
    Rails.cache.write("channex:ari:window:#{hotel.id}", {
      'min_date' => '2026-05-10',
      'max_date' => '2026-05-12',
      'sync_availability' => true,
      'sync_rates' => true,
      'sync_restrictions' => true,
      'room_type_windows' => {},
      'rate_plan_windows' => {},
      'rate_plan_fields' => {}
    })
    Rails.cache.write("channex:ari:scheduled:#{hotel.id}", true)

    expect(ChannelManagers::SyncJob).to receive(:perform_later).with(
      hotel.id,
      Date.new(2026, 5, 10),
      Date.new(2026, 5, 12),
      sync_availability: true,
      sync_rates: true,
      sync_restrictions: true,
      room_type_ids: {},
      rate_plan_ids: {},
      rate_plan_fields: {}
    )

    described_class.perform_now(hotel.id)

    expect(Rails.cache.read("channex:ari:window:#{hotel.id}")).to be_nil
    expect(Rails.cache.read("channex:ari:scheduled:#{hotel.id}")).to be_nil
  end

  context "when a change arrives while the push is running" do
    it "sends that change on the next flush instead of clearing it" do
      ChannelManagers::BufferAriSyncJob.perform_now(hotel.id, Date.new(2026, 11, 5), type: :availability, room_type_id: 1)
      clear_enqueued_jobs

      allow(ChannelManagers::SyncJob).to receive(:perform_later) do
        ChannelManagers::BufferAriSyncJob.perform_now(hotel.id, Date.new(2026, 11, 20), type: :availability, room_type_id: 2)
      end

      described_class.perform_now(hotel.id)

      window = Rails.cache.read("channex:ari:window:#{hotel.id}")
      expect(window).to include("min_date" => "2026-11-20", "max_date" => "2026-11-20")
      expect(window["room_type_windows"].keys).to eq([ "2" ])
      expect(described_class).to have_been_enqueued.with(hotel.id)
    end
  end

  context "when the push fails" do
    it "puts the changes back for the retry" do
      ChannelManagers::BufferAriSyncJob.perform_now(hotel.id, Date.new(2026, 11, 5), type: :availability, room_type_id: 1)
      allow(ChannelManagers::SyncJob).to receive(:perform_later).and_raise(ActiveRecord::ConnectionTimeoutError)

      expect { described_class.perform_now(hotel.id) }.to raise_error(ActiveRecord::ConnectionTimeoutError)

      window = Rails.cache.read("channex:ari:window:#{hotel.id}")
      expect(window["room_type_windows"]).to eq("1" => { "min" => "2026-11-05", "max" => "2026-11-05" })
    end
  end
end
