require 'rails_helper'

RSpec.describe 'Channex onboarding flow' do
  let(:hotel) { create(:hotel, preferred_channel_manager: 'channex', name: 'Flow Hotel', city: 'Kuching') }
  let!(:room_type) { create(:room_type, hotel: hotel, name: 'Deluxe', quantity: 3, max_adults: 2) }
  let!(:rate_plan) do
    # Use auto-created plan and rename it to BAR
    plan = room_type.rate_plans.first
    plan.update!(name: 'BAR')
    plan
  end
  let(:client_double) { instance_double(Channex::Client) }

  before do
    allow(Channex::Client).to receive(:new).and_return(client_double)
  end

  it 'creates property, room type, and rate plan mappings' do
    expect(client_double).to receive(:post).with('/properties', hash_including(property: hash_including(title: 'Flow Hotel')))
      .and_return({ 'data' => { 'id' => 'prop_1' } })
    expect(client_double).to receive(:post).with('/room_types', hash_including(room_type: hash_including(property_id: 'prop_1', title: 'Deluxe')))
      .and_return({ 'data' => { 'id' => 'rt_1' } })
    expect(client_double).to receive(:post).with('/rate_plans', hash_including(rate_plan: hash_including(room_type_id: 'rt_1', title: 'BAR (Deluxe)')))
      .and_return({ 'data' => { 'id' => 'rp_1' } })

    result = ChannelManagers::OnboardingService.new(hotel: hotel).call

    expect(result.success?).to be(true)
    expect(hotel.channel_mapping.external_id).to eq('prop_1')
    expect(room_type.channel_mapping.external_id).to eq('rt_1')
    expect(room_type.room_type_rate_plans.find_by!(rate_plan: rate_plan).channel_mapping.external_id).to eq('rp_1')
  end
end
