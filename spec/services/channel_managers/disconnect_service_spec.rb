require "rails_helper"

RSpec.describe ChannelManagers::DisconnectService, type: :service do
  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }

  subject { described_class.new(hotel: hotel) }

  describe "#call" do
    it "clears channel manager settings" do
      result = subject.call
      expect(result.success?).to be true
      expect(hotel.reload.preferred_channel_manager).to be_nil
    end
  end
end
