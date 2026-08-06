# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelOps::BulkUpdateRates do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:rate_plan) { create(:rate_plan, room_type: room_type, currency: "MYR") }
  let(:user) { create(:user) }
  let(:start_date) { Date.current }
  let(:end_date) { Date.current + 2.days }
  let(:price) { 150.0 }

  subject do
    described_class.new(
      hotel: hotel,
      rate_plan: rate_plan,
      start_date: start_date,
      end_date: end_date,
      price: price,
      user: user
    )
  end

  it "updates rates for the given date range" do
    expect {
      result = subject.call
      expect(result[:success]).to be(true)
    }.to change(RoomRate, :count).by(3)

    room_rates = rate_plan.room_rates.where(date: start_date..end_date)
    expect(room_rates.count).to eq(3)
    expect(room_rates.pluck(:price).uniq).to eq([ price ])
  end

  it "logs audit entries for price changes" do
    expect {
      subject.call
    }.to change(InventoryAuditLog, :count).by(3)

    log = InventoryAuditLog.last
    expect(log.action_type).to eq("rate_update")
    expect(log.hotel_id).to eq(hotel.id)
  end

  it "triggers ARI sync if channel manager is connected" do
    hotel.update(preferred_channel_manager: "channex")
    ActiveJob::Base.queue_adapter = :test

    expect {
      subject.call
    }.to enqueue_job(ChannelManagers::SyncJob).at_least(:once)
  end
end
