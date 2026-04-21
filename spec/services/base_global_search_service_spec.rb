require "rails_helper"

RSpec.describe BaseGlobalSearchService do
  subject(:service) { described_class.new("dashboard") }

  it "scores exact includes higher than blank query" do
    expect(service.search_score("admin dashboard", "dashboard")).to be > service.search_score("admin dashboard", "")
  end

  it "tokenizes alphanumeric words" do
    expect(service.tokenize("Hello-123 world")).to eq(%w[hello 123 world])
  end

  it "detects subsequence matches" do
    expect(service.subsequence_match?("dsh", "dashboard")).to be(true)
    expect(service.subsequence_match?("xyz", "dashboard")).to be(false)
  end
end
