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

    it "supports legacy key_id/key_secret fields" do
      credentials = {
        payments: {
          gateways: {
            razorpay: {
              key_id: "legacy_key",
              key_secret: "legacy_secret"
            }
          }
        }
      }.deep_symbolize_keys

      allow(Rails.application).to receive(:credentials).and_return(credentials)

      setting = described_class.for_gateway("razorpay")
      expect(setting.api_key).to eq("legacy_key")
      expect(setting.secret_key).to eq("legacy_secret")
    end

    it "returns nil when gateway is missing" do
      allow(Rails.application).to receive(:credentials).and_return({ payments: { gateways: {} } }.deep_symbolize_keys)

      expect(described_class.for_gateway("unknown")).to be_nil
    end

    it "returns nil when credentials are incomplete" do
      credentials = {
        payments: {
          gateways: {
            razorpay: { api_key: "only_key" }
          }
        }
      }.deep_symbolize_keys

      allow(Rails.application).to receive(:credentials).and_return(credentials)

      expect(described_class.for_gateway("razorpay")).to be_nil
    end
  end

  describe ".default" do
    it "returns default gateway setting from nested default.gateway" do
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

    it "supports payments.default_gateway" do
      credentials = {
        payments: {
          default_gateway: "curlec",
          gateways: {
            curlec: {
              api_key: "curlec_key",
              secret_key: "curlec_secret"
            }
          }
        }
      }.deep_symbolize_keys

      allow(Rails.application).to receive(:credentials).and_return(credentials)

      setting = described_class.default
      expect(setting.gateway).to eq("curlec")
    end

    it "returns nil when default gateway not configured" do
      allow(Rails.application).to receive(:credentials).and_return({ payments: {} }.deep_symbolize_keys)
      expect(described_class.default).to be_nil
    end
  end
end
