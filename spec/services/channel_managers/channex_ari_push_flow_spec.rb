require 'rails_helper'

RSpec.describe 'Channex ARI push flow' do
  let(:hotel) { create(:hotel, preferred_channel_manager: 'channex') }
  let(:room_type) { create(:room_type, hotel: hotel, name: 'Deluxe') }
  let(:rate_plan) { create(:rate_plan, room_type: room_type, name: 'BAR', currency: 'MYR') }
  let(:client_double) { instance_double(Channex::Client) }

  before do
    create(:channel_mapping, mappable: hotel, provider: 'channex', external_id: 'prop_1')
    create(:channel_mapping, mappable: room_type, provider: 'channex', external_id: 'rt_1')
    room_type_rate_plan = room_type.room_type_rate_plans.find_by!(rate_plan: rate_plan)
    create(:channel_mapping, mappable: room_type_rate_plan, provider: 'channex', external_id: 'rp_1')

    create(:room_inventory, room_type: room_type, date: Date.new(2026, 6, 1), quantity: 2, status: 'open')
    create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: Date.new(2026, 6, 1), price: 200, currency: 'MYR')

    allow(Channex::Client).to receive(:new).and_return(client_double)
    allow(client_double).to receive(:get).with('/channels').and_return({ 'data' => [] })
  end

  it 'posts availability and restrictions payloads successfully' do
    expect(client_double).to receive(:post).with('/availability', hash_including(values: array_including(hash_including(property_id: 'prop_1', room_type_id: 'rt_1'))))
      .and_return({ 'data' => [] })
    expect(client_double).to receive(:post).with('/restrictions', hash_including(values: array_including(hash_including(property_id: 'prop_1', rate_plan_id: 'rp_1'))))
      .and_return({ 'data' => [] })

    result = ChannelManagers::SyncOrchestrator.adapter_for(hotel).push_ari(date_range: (Date.new(2026, 6, 1)..Date.new(2026, 6, 1)))

    expect(result.success?).to be(true)
  end

  context 'when one rate plan is shared across room categories' do
    let(:suite) { create(:room_type, hotel: hotel, name: 'Suite') }

    before do
      create(:channel_mapping, mappable: suite, provider: 'channex', external_id: 'rt_2')
      create(:room_type_rate_plan, rate_plan: rate_plan, room_type: suite)
      shared_join = suite.room_type_rate_plans.find_by!(rate_plan: rate_plan)
      create(:channel_mapping, mappable: shared_join, provider: 'channex', external_id: 'rp_2')

      create(:room_inventory, room_type: suite, date: Date.new(2026, 6, 1), quantity: 1, status: 'open')
      create(:room_rate, room_type: suite, rate_plan: rate_plan, date: Date.new(2026, 6, 1), price: 500, currency: 'MYR')
    end

    it 'pushes each room category at its own price' do
      allow(client_double).to receive(:post).with('/availability', anything).and_return({ 'data' => [] })

      pushed = nil
      expect(client_double).to receive(:post).with('/restrictions', anything) do |_path, payload|
        pushed = payload[:values]
        { 'data' => [] }
      end

      ChannelManagers::SyncOrchestrator.adapter_for(hotel).push_ari(date_range: (Date.new(2026, 6, 1)..Date.new(2026, 6, 1)))

      expect(pushed).to include(hash_including(rate_plan_id: 'rp_1', rate: '200.00'))
      expect(pushed).to include(hash_including(rate_plan_id: 'rp_2', rate: '500.00'))
    end
  end
end
