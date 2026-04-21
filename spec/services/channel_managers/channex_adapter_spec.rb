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
end
