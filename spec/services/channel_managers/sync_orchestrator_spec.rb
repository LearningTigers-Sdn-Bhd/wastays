require "rails_helper"

RSpec.describe ChannelManagers::SyncOrchestrator do
  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }

  it "returns the correct adapter for a hotel" do
    adapter = described_class.adapter_for(hotel)
    expect(adapter).to be_a(ChannelManagers::ChannexAdapter)
  end

  it "raises error for unsupported provider" do
    hotel.update(preferred_channel_manager: "unsupported")
    expect { described_class.adapter_for(hotel) }.to raise_error("Unsupported channel manager: unsupported")
  end
end
