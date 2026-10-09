# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channex::AriRateLimiter do
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(cache_store) }

  def body(property_id)
    { values: [ { property_id: property_id, date_from: "2026-11-10", date_to: "2026-11-10", availability: 1 } ] }
  end

  it "allows five calls a minute per property and endpoint, then holds the rest", frozen_time: Time.zone.local(2026, 11, 1, 10, 0, 5) do
    results = Array.new(6) { described_class.allow?("/availability", body("prop-1")) }

    expect(results).to eq([ true, true, true, true, true, false ])
  end

  it "keeps separate budgets per endpoint and per property", frozen_time: Time.zone.local(2026, 11, 1, 10, 0, 5) do
    5.times { described_class.allow?("/availability", body("prop-1")) }

    expect(described_class.allow?("/restrictions", body("prop-1"))).to be(true)
    expect(described_class.allow?("/availability", body("prop-2"))).to be(true)
  end

  it "frees the budget in the next minute" do
    travel_to(Time.zone.local(2026, 11, 1, 10, 0, 50)) { 5.times { described_class.allow?("/availability", body("prop-1")) } }

    travel_to(Time.zone.local(2026, 11, 1, 10, 1, 1)) do
      expect(described_class.allow?("/availability", body("prop-1"))).to be(true)
    end
  end

  it "reports room only when every endpoint a push needs has budget left", frozen_time: Time.zone.local(2026, 11, 1, 10, 0, 5) do
    5.times { described_class.allow?("/restrictions", body("prop-1")) }

    expect(described_class.room_for?("prop-1", [ "/availability" ])).to be(true)
    expect(described_class.room_for?("prop-1", [ "/availability", "/restrictions" ])).to be(false)
    expect(described_class.allow?("/availability", body("prop-1"))).to be(true) # checking spent nothing
  end

  it "never limits calls outside the ARI endpoints" do
    expect(Array.new(10) { described_class.allow?("/channel_availability_rules", {}) }).to all(be(true))
  end

  describe "through the client" do
    it "answers a retryable 429 without calling Channex once the budget is spent", frozen_time: Time.zone.local(2026, 11, 1, 10, 0, 5) do
      client = Channex::Client.new(api_key: "key")
      5.times { described_class.allow?("/availability", body("prop-1")) }
      allow(Net::HTTP).to receive(:new)

      response = client.post("/availability", body("prop-1"))

      expect(response).to include(status: "429", retryable: true)
      expect(Net::HTTP).not_to have_received(:new)
    end
  end
end
