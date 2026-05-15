require 'rails_helper'

RSpec.describe ChannelManagers::FullRefreshService do
  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
  let(:service) { described_class.new(hotel: hotel) }

  describe '#call' do
    it 'triggers ARI sync for a long window' do
      expect(ChannelManagers::SyncJob).to receive(:perform_later).with(hotel.id, anything, anything)
      service.call
    end
  end
end
