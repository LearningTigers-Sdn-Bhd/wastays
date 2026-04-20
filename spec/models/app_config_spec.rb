require "rails_helper"

RSpec.describe AppConfig, type: :model do
  describe ".get" do
    it "returns nil for a missing key" do
      expect(AppConfig.get("nonexistent_key")).to be_nil
    end

    it "returns the value for an existing key" do
      AppConfig.set("webhook_url", "https://example.com/hook")
      expect(AppConfig.get("webhook_url")).to eq("https://example.com/hook")
    end
  end

  describe ".set" do
    it "creates a new record when key does not exist" do
      expect { AppConfig.set("webhook_url", "https://example.com") }
        .to change(AppConfig, :count).by(1)
    end

    it "updates an existing record when key already exists" do
      AppConfig.set("webhook_url", "https://first.com")
      expect { AppConfig.set("webhook_url", "https://second.com") }
        .not_to change(AppConfig, :count)
      expect(AppConfig.get("webhook_url")).to eq("https://second.com")
    end
  end
end
