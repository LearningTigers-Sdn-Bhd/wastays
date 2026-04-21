require "rails_helper"

RSpec.describe Payments::GatewayRegistry do
  let(:setting) { Payments::CredentialSetting::Setting.new(gateway: "razorpay", api_key: "k", secret_key: "s", status: "active") }

  describe ".fetch" do
    it "returns razorpay adapter" do
      adapter = described_class.fetch(gateway: "razorpay", setting: setting)
      expect(adapter).to be_a(Payments::GatewayAdapters::Razorpay)
    end

    it "normalizes gateway case" do
      adapter = described_class.fetch(gateway: "CuRlEc", setting: setting)
      expect(adapter).to be_a(Payments::GatewayAdapters::Curlec)
    end

    it "raises for unsupported gateway" do
      expect {
        described_class.fetch(gateway: "stripe", setting: setting)
      }.to raise_error(Payments::GatewayRegistry::UnsupportedGatewayError, /Unsupported gateway: stripe/)
    end
  end
end
