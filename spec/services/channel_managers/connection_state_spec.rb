# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::ConnectionState do
  describe ".provisioned?" do
    let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }

    it "recognizes a supported provider with a completed external mapping" do
      create(:channel_mapping, mappable: hotel, provider: "channex", external_id: "property-123")

      expect(described_class.provisioned?(hotel)).to be(true)
    end

    it "rejects a pending external mapping" do
      create(:channel_mapping, mappable: hotel, provider: "channex", external_id: "pending-property-123")

      expect(described_class.provisioned?(hotel)).to be(false)
    end

    it "rejects an unsupported provider even when a mapping exists" do
      hotel.update!(preferred_channel_manager: "unsupported")
      create(:channel_mapping, mappable: hotel, provider: "unsupported", external_id: "property-123")

      expect(described_class.provisioned?(hotel)).to be(false)
    end
  end
end
