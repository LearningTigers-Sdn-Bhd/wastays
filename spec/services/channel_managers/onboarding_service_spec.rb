require 'rails_helper'

RSpec.describe ChannelManagers::OnboardingService do
  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
  let(:service) { described_class.new(hotel: hotel) }
  let(:adapter_double) { instance_double(ChannelManagers::ChannexAdapter) }

  before do
    allow(ChannelManagers::SyncOrchestrator).to receive(:adapter_for).with(hotel).and_return(adapter_double)
  end

  describe '#call' do
    it 'delegates onboarding to the correct adapter' do
      expect(adapter_double).to receive(:onboard_hotel).and_return(OpenStruct.new(success?: true))

      result = service.call
      expect(result.success?).to be true
    end

    it 'returns failure if CM not selected' do
      hotel.update(preferred_channel_manager: nil)
      result = service.call
      expect(result.success?).to be false
      expect(result.message).to eq("Channel manager not selected for this hotel")
    end
  end
end
