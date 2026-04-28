require "rails_helper"

RSpec.describe Admin::Hotels::OnboardChannexService, type: :service do
  let(:hotel) { create(:hotel) }
  let(:onboarding_result) { double("Result", success?: true, message: "Success") }

  before do
    allow(ChannelManagers::OnboardingService).to receive(:new).with(hotel: hotel).and_return(double(call: onboarding_result))
  end

  subject { described_class.new(hotel: hotel) }

  describe "#call" do
    it "sets preferred channel manager and calls onboarding service" do
      result = subject.call
      expect(hotel.reload.preferred_channel_manager).to eq("channex")
      expect(result.success?).to be true
    end
  end
end
