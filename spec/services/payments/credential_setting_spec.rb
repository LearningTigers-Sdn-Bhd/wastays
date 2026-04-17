require "rails_helper"

RSpec.describe Payments::CredentialSetting do
  describe ".for_gateway" do
    it "builds a setting from credentials gateway config" do
      credentials = {
        payments: {
          gateways: {
            razorpay: {
              api_key: "rzp_test_key",
              secret_key: "rzp_test_secret",
              webhook_secret: "whsec"
            }
          }
        }
      }.deep_symbolize_keys

      allow(Rails.application).to receive(:credentials).and_return(credentials)

      setting = described_class.for_gateway("razorpay")

      expect(setting.gateway).to eq("razorpay")
      expect(setting.api_key).to eq("rzp_test_key")
      expect(setting.secret_key).to eq("rzp_test_secret")
      expect(setting.webhook_secret).to eq("whsec")
      expect(setting.status).to eq("active")
    end
  end

  describe ".default" do
    it "returns default gateway setting from credentials" do
      credentials = {
        payments: {
          default: { gateway: "razorpay" },
          gateways: {
            razorpay: {
              api_key: "rzp_live_key",
              secret_key: "rzp_live_secret"
            }
          }
        }
      }.deep_symbolize_keys

      allow(Rails.application).to receive(:credentials).and_return(credentials)

      setting = described_class.default
      expect(setting.gateway).to eq("razorpay")
    end
  end
end
