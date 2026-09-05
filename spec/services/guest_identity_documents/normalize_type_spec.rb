# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestIdentityDocuments::NormalizeType do
  describe ".call" do
    it "keeps a Malaysian identity card as a MyKad" do
      expect(described_class.call(value: "ic", country: "Malaysia")).to eq("malaysian_nric")
    end

    it "treats an identity card from another country as a national identity card" do
      expect(described_class.call(value: "ic", country: "Singapore")).to eq("national_id")
    end

    it "assumes Malaysia when the country is missing" do
      expect(described_class.call(value: "ic", country: nil)).to eq("malaysian_nric")
    end

    it "leaves an already normalized type alone when the country changes" do
      expect(described_class.call(value: "malaysian_nric", country: "Singapore")).to eq("malaysian_nric")
    end

    it "keeps a passport" do
      expect(described_class.call(value: "passport", country: "Japan")).to eq("passport")
    end

    it "returns nil for an unknown value" do
      expect(described_class.call(value: "driver_licence", country: "Malaysia")).to be_nil
    end
  end

  describe ".country_code" do
    it "returns MYS for Malaysia" do
      expect(described_class.country_code("Malaysia")).to eq("MYS")
    end

    it "returns the alpha-3 code for another country" do
      expect(described_class.country_code("Singapore")).to eq("SGP")
    end

    it "returns nil for an unknown country" do
      expect(described_class.country_code("Atlantis")).to be_nil
    end
  end
end
