require 'rails_helper'

RSpec.describe RoomRate, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:room_type) }
  end

  describe 'validations' do
    subject(:room_rate) { create(:room_rate) }

    it { is_expected.to validate_presence_of(:date) }
    it { is_expected.to validate_presence_of(:price) }
    it { is_expected.to validate_numericality_of(:price).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_presence_of(:currency) }
    it { is_expected.to validate_uniqueness_of(:date).scoped_to(:room_type_id, :rate_plan_id, :currency).case_insensitive }
  end


  it "rejects adult occupancy prices above the room category capacity" do
    rate = build(:room_rate, room_type: create(:room_type, max_adults: 2), occupancy_prices: { "3" => 500 })

    expect(rate).not_to be_valid
    expect(rate.errors[:occupancy_prices]).to include("contains an adult occupancy outside the room category capacity")
  end

  describe "Channex push on save" do
    include ActiveJob::TestHelper

    let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
    let(:room_type) { create(:room_type, hotel: hotel) }
    let!(:rate) { create(:room_rate, room_type: room_type, rate_plan: room_type.rate_plans.first, date: Date.current + 30, price: 100) }

    before { clear_enqueued_jobs }

    def buffered_types
      enqueued_jobs.select { |job| job["job_class"] == "ChannelManagers::BufferAriSyncJob" }
        .map { |job| job["arguments"].last["type"]["value"] }
    end

    it "sends a price change as a rate, so the new price reaches the OTAs" do
      rate.update!(price: 205)

      expect(buffered_types).to eq([ "rates" ])
    end

    it "sends a restriction change as a restriction" do
      rate.update!(min_stay: 3)

      expect(buffered_types).to eq([ "restrictions" ])
    end

    it "sends both when both change" do
      rate.update!(price: 210, stop_sell: true)

      expect(buffered_types).to contain_exactly("rates", "restrictions")
    end
  end
end
