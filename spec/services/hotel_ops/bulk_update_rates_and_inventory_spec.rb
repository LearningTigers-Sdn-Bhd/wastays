# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelOps::BulkUpdateRatesAndInventory do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let!(:rate_plan) { room_type.rate_plans.first }
  let(:user) { create(:user, account: hotel.account) }

  it "delegates to bulk rate and inventory updaters" do
    rate_updater = instance_double(HotelOps::BulkUpdateRates, call: { success: true })
    inv_updater = instance_double(HotelOps::BulkUpdateInventory, call: { success: true })

    expect(HotelOps::BulkUpdateRates).to receive(:new).with(
      hotel: hotel,
      rate_plan: rate_plan,
      start_date: Date.current,
      end_date: Date.current + 1,
      price: 150.0,
      user: user
    ).and_return(rate_updater)

    expect(HotelOps::BulkUpdateInventory).to receive(:new).and_return(inv_updater)

    result = described_class.new(
      hotel: hotel,
      room_type_ids: [ room_type.id ],
      rate_plan_ids: [ rate_plan.id ],
      start_date: Date.current,
      end_date: Date.current + 1,
      price: 150,
      quantity: 3,
      status: "open",
      user: user
    ).call

    expect(result[:success]).to be(true)
  end

  context "when the hotel is connected to Channex" do
    let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }

    it "queues one push for a close, not another per saved row" do
      create(:room_inventory, room_type: room_type, date: Date.current, quantity: 3, status: "open")

      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      described_class.new(
        hotel: hotel, room_type_ids: [ room_type.id ], start_date: Date.current, end_date: Date.current,
        status: "closed", user: user
      ).call

      queued = ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job["job_class"] }
      expect(queued.count("ChannelManagers::SyncJob")).to eq(1)
      expect(queued).not_to include("ChannelManagers::BufferAriSyncJob")
    end
  end
end
