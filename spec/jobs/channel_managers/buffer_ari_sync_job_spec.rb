require "rails_helper"

RSpec.describe ChannelManagers::BufferAriSyncJob, type: :job do
  include ActiveJob::TestHelper

  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache_store)
    Rails.cache.clear
    clear_enqueued_jobs
  end

  it "coalesces dates and schedules a single flush job" do
    described_class.perform_now(hotel.id, Date.new(2026, 5, 10), type: :availability)
    described_class.perform_now(hotel.id, Date.new(2026, 5, 12), type: :restrictions)

    window = Rails.cache.read("channex:ari:window:#{hotel.id}")
    expect(window).to eq({
      "min_date" => "2026-05-10",
      "max_date" => "2026-05-12",
      "sync_availability" => true,
      "sync_rates" => false,
      "sync_restrictions" => true,
      "room_type_windows" => {},
      "rate_plan_windows" => {},
      "rate_plan_fields" => {}
    })

    jobs = enqueued_jobs.select { |job| job[:job] == ChannelManagers::FlushAriSyncJob }
    expect(jobs.size).to eq(1)
  end
end
