# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoice::MalaysiaStates do
  describe ".resolve" do
    it "prefers an explicit state code over anything inferred from the city" do
      # The guest picked Selangor; the city text must not override that.
      expect(described_class.resolve(state_code: "10", city: "kuala lumpur", country_code: "MYS")).to eq("10")
    end

    it "files a non-Malaysian buyer as not applicable" do
      expect(described_class.resolve(state_code: nil, city: "London", country_code: "GBR")).to eq("17")
    end

    it "falls back to the city for records captured before the state field existed" do
      expect(described_class.resolve(state_code: nil, city: "Kota Kinabalu", country_code: "MYS")).to eq("12")
    end

    it "resolves cities the original 15-city map rejected outright" do
      # These are large towns; under the old lookup each raised and failed the
      # whole submission.
      expect(described_class.resolve(state_code: nil, city: "Petaling Jaya", country_code: "MYS")).to eq("10")
      expect(described_class.resolve(state_code: nil, city: "Miri", country_code: "MYS")).to eq("13")
      expect(described_class.resolve(state_code: nil, city: "Kuala Terengganu", country_code: "MYS")).to eq("11")
    end

    it "returns nil when a Malaysian city cannot be resolved, rather than guessing" do
      expect(described_class.resolve(state_code: nil, city: "Nowhereville", country_code: "MYS")).to be_nil
    end

    it "ignores an invalid state code and keeps looking" do
      expect(described_class.resolve(state_code: "99", city: "Ipoh", country_code: "MYS")).to eq("08")
    end
  end

  describe ".options" do
    it "lists every state alphabetically with not-applicable last" do
      options = described_class.options

      expect(options.length).to eq(17)
      expect(options.first.first).to eq("Johor")
      expect(options.last.last).to eq("17")
    end
  end
end
