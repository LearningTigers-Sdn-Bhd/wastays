require "rails_helper"

RSpec.describe Concierge::QrSvg do
  describe ".for" do
    it "returns a plain SVG string" do
      result = described_class.for("https://wastays.com/h/sample/concierge")
      expect(result).to include("<svg")
      expect(result).not_to be_html_safe
    end
  end

  describe ".png" do
    it "returns a binary PNG string" do
      result = described_class.png("https://wastays.com/h/sample/concierge")
      expect(result).to be_a(String)
      expect(result.encoding).to eq(Encoding::ASCII_8BIT).or eq(Encoding::BINARY)
    end
  end
end
