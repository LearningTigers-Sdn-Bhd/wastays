require "rails_helper"

RSpec.describe ChannelManagers::FlushAriSyncJob, type: :job do
  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache_store)
    Rails.cache.clear
  end

  it "flushes buffered window via sync job and clears cache keys" do
    Rails.cache.write("channex:ari:window:#{hotel.id}", { "min_date" => "2026-05-10", "max_date" => "2026-05-12" })
    Rails.cache.write("channex:ari:scheduled:#{hotel.id}", true)

    expect(ChannelManagers::SyncJob).to receive(:perform_now).with(hotel.id, Date.new(2026, 5, 10), Date.new(2026, 5, 12))

    described_class.perform_now(hotel.id)

    expect(Rails.cache.read("channex:ari:window:#{hotel.id}")).to be_nil
    expect(Rails.cache.read("channex:ari:scheduled:#{hotel.id}")).to be_nil
  end
end
