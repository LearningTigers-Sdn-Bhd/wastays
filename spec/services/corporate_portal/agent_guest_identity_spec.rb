# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporatePortal::AgentGuestIdentity do
  subject(:identity) { Class.new { include CorporatePortal::AgentGuestIdentity }.new }

  def route(country, id_number) = identity.send(:identity_attributes, country: country, id_number: id_number)

  it "files a Malaysian IC as an NRIC" do
    expect(route("Malaysia", "900402-12-5566")).to eq(document_type: "malaysian_nric", government_id: "900402-12-5566")
  end

  it "keeps a malformed IC without claiming it is an NRIC" do
    expect(route("Malaysia", "9004021z5566")).to eq(government_id: "9004021z5566")
  end

  it "files anyone else's number as a passport, stripped of spaces and hyphens" do
    expect(route("Singapore", "K12 345-67")).to eq(document_type: "passport", passport_number: "K1234567")
  end

  it "routes nothing without a number or a country" do
    expect(route("Malaysia", "")).to eq({})
    expect(route(nil, "K1234567")).to eq({})
  end
end
