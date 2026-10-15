# frozen_string_literal: true

require "rails_helper"

RSpec.describe ObservationDeck::PayloadScrubber do
  def scrub(headers)
    described_class.filter(request_headers: headers)[:request_headers]
  end

  it "masks the Channex API key header" do
    expect(scrub("user-api-key" => [ "live-secret" ])).to eq("user-api-key" => "[FILTERED]")
  end

  it "masks a Basic Authorization header" do
    expect(scrub("authorization" => [ "Basic abc=" ])).to eq("authorization" => "[FILTERED]")
  end

  it "keeps harmless headers and email readable for debugging" do
    result = described_class.filter(
      request_headers: { "content-type" => [ "application/json" ] },
      request_body: { "email" => "guest@example.com" }
    )

    expect(result[:request_headers]).to eq("content-type" => [ "application/json" ])
    expect(result[:request_body]).to eq("email" => "guest@example.com")
  end
end
