# frozen_string_literal: true

require "rails_helper"
require "fugit"

RSpec.describe ChannelManagers::NightlyFullRefreshJob, type: :job do
  def connected_hotel(external_id: "prop_#{SecureRandom.hex(3)}", **attrs)
    create(:hotel, preferred_channel_manager: "channex", **attrs).tap do |hotel|
      create(:channel_mapping, mappable: hotel, provider: "channex", external_id: external_id)
    end
  end

  it "queues a full refresh for each provisioned Channex hotel" do
    hotel = connected_hotel
    today = hotel.hotel_time_zone.today

    expect { described_class.perform_now }
      .to have_enqueued_job(ChannelManagers::SyncJob).with(hotel.id, today, today + 499.days, hash_including(sync_availability: true, sync_rates: true))
  end

  it "spaces the hotels' refreshes a few seconds apart", frozen_time: Time.zone.local(2026, 11, 9, 18, 0) do
    first = connected_hotel
    second = connected_hotel

    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    described_class.perform_now

    scheduled = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job["job_class"] == "ChannelManagers::SyncJob" }
      .to_h { |job| [ job["arguments"].first, job[:at] ] }
    expect(scheduled[second.id] - scheduled[first.id]).to be_within(0.01).of(5)
  end

  it "skips hotels with no channel manager, or one that is only 'undecided'" do
    create(:hotel, preferred_channel_manager: "undecided")
    create(:hotel, preferred_channel_manager: "none")
    create(:hotel, preferred_channel_manager: nil)

    expect { described_class.perform_now }.not_to have_enqueued_job(ChannelManagers::SyncJob)
  end

  it "skips a hotel whose Channex property was never created" do
    hotel = create(:hotel, preferred_channel_manager: "channex")
    create(:channel_mapping, mappable: hotel, provider: "channex", external_id: "pending_123")

    expect { described_class.perform_now }.not_to have_enqueued_job(ChannelManagers::SyncJob)
  end

  it "skips a hotel with no mapping at all" do
    create(:hotel, preferred_channel_manager: "channex")

    expect { described_class.perform_now }.not_to have_enqueued_job(ChannelManagers::SyncJob)
  end

  it "queues every connected hotel even when another one is skipped" do
    first = connected_hotel
    create(:hotel, preferred_channel_manager: "channex")
    second = connected_hotel

    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    described_class.perform_now

    sync_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job["job_class"] == "ChannelManagers::SyncJob" }
    expect(sync_jobs.map { |job| job["arguments"].first }).to contain_exactly(first.id, second.id)
  end

  it "is scheduled nightly at 2am Kuala Lumpur time in production" do
    entry = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "nightly_channex_full_refresh")

    expect(entry["class"]).to eq("ChannelManagers::NightlyFullRefreshJob")
    cron = Fugit.parse(entry["schedule"])
    expect(cron).to be_a(Fugit::Cron)
    expect(cron.timezone.name).to eq("Asia/Kuala_Lumpur")
    expect(cron.hours).to eq([ 2 ])
  end
end
