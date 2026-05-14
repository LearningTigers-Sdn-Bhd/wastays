require 'rails_helper'

RSpec.describe ChannelManagers::ChannexAdapter do
  let(:hotel) { create(:hotel, name: "Test Hotel", city: "KL") }
  let!(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe", quantity: 5, max_adults: 2) }
  let(:adapter) { described_class.new(hotel: hotel) }
  let(:client_double) { instance_double(Channex::Client) }

  before do
    allow(Channex::Client).to receive(:new).and_return(client_double)
  end

  describe '#onboard_hotel' do
    it 'creates property, room types and rate plans' do
      # Mock Property Creation
      expect(client_double).to receive(:post).with("/properties", hash_including(property: hash_including(title: "Test Hotel", timezone: "Asia/Kuala_Lumpur")))
        .and_return({ "data" => { "id" => "ch_prop_123" } })

      # Mock Room Type Creation
      expect(client_double).to receive(:post).with("/room_types", hash_including(room_type: hash_including(title: "Deluxe", property_id: "ch_prop_123")))
        .and_return({ "data" => { "id" => "ch_rt_123" } })

      # Mock Rate Plan Creation
      expect(client_double).to receive(:post).with("/rate_plans", hash_including(rate_plan: hash_including(title: "Standard Rate", room_type_id: "ch_rt_123")))
        .and_return({ "data" => { "id" => "ch_rp_123" } })

      result = adapter.onboard_hotel

      expect(result.success?).to be true
      expect(hotel.channel_mapping.external_id).to eq("ch_prop_123")
      expect(room_type.channel_mapping.external_id).to eq("ch_rt_123")
      expect(room_type.rate_plans.first.channel_mapping.external_id).to eq("ch_rp_123")
    end
  end

  describe '#push_ari' do
    let(:start_date) { Date.current }
    let(:end_date) { start_date + 2.days }
    let!(:rate_plan) { create(:rate_plan, room_type: room_type, name: "Standard Rate") }

    before do
      # Setup mappings
      hotel.create_channel_mapping(provider: "channex", external_id: "ch_prop_123")
      room_type.create_channel_mapping(provider: "channex", external_id: "ch_rt_123")
      rate_plan.create_channel_mapping(provider: "channex", external_id: "ch_rp_123")

      # Create ARI data - ensure contiguous dates with SAME values for grouping
      (start_date..end_date).each do |date|
        room_type.room_inventories.create!(date: date, quantity: 10, status: "open")
        rate_plan.room_rates.create!(date: date, price: 200.0, currency: "MYR", room_type: room_type)
      end
    end

    it 'optimizes the payload using date ranges (date_from and date_to)' do
      # Expect availability to be grouped into ONE range
      expect(client_double).to receive(:post).with("/availability", {
        values: [
          {
            property_id: "ch_prop_123",
            room_type_id: "ch_rt_123",
            date_from: start_date.to_s,
            date_to: end_date.to_s,
            availability: 10
          }
        ]
      }).and_return({ "data" => { "id" => "task_1" } })

      # Expect restrictions/rates to be grouped into ONE range
      expect(client_double).to receive(:post).with("/restrictions", {
        values: [
          {
            property_id: "ch_prop_123",
            rate_plan_id: "ch_rp_123",
            date_from: start_date.to_s,
            date_to: end_date.to_s,
            rate: "200.00",
            currency: "MYR",
            occupancy: 2
          }
        ]
      }).and_return({ "data" => { "id" => "task_2" } })

      result = adapter.push_ari(date_range: (start_date..end_date))
      expect(result.success?).to be true
    end

    it 'creates multiple ranges for non-contiguous dates or different values' do
      # Add a fourth day with a DIFFERENT price
      diff_date = start_date + 3.days
      rate_plan.room_rates.create!(date: diff_date, price: 300.0, currency: "MYR", room_type: room_type)
      room_type.room_inventories.create!(date: diff_date, quantity: 10, status: "open")

      # Expect 2 restriction ranges due to different price
      expect(client_double).to receive(:post).with("/restrictions", hash_including(
        values: array_including(
          hash_including(date_from: start_date.to_s, date_to: end_date.to_s, rate: "200.00"),
          hash_including(date_from: diff_date.to_s, date_to: diff_date.to_s, rate: "300.00")
        )
      )).and_return({ "data" => { "id" => "task_2" } })

      # Expect 1 availability range because availability is same (10) and dates are contiguous
      expect(client_double).to receive(:post).with("/availability", hash_including(
        values: [
          hash_including(date_from: start_date.to_s, date_to: diff_date.to_s, availability: 10)
        ]
      )).and_return({ "data" => { "id" => "task_1" } })

      result = adapter.push_ari(date_range: (start_date..diff_date))
      expect(result.success?).to be true
    end
  end
end
