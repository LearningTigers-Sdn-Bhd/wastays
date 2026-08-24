# frozen_string_literal: true

require "rails_helper"

RSpec.describe Attractions::GoogleMapsUrlParser do
  subject(:result) { described_class.call(url) }

  let(:url) do
    "https://www.google.com/maps/place/Tunku+Abdul+Rahman+Marine+Park/@5.971,116.058,13z/data=!4m6!3m5!1sabc!8m2!3d5.97521!4d116.06432"
  end

  it "extracts the place name and final data coordinates" do
    expect(result).to be_success
    expect(result.parsed.name).to eq("Tunku Abdul Rahman Marine Park")
    expect(result.parsed.latitude).to eq(BigDecimal("5.97521"))
    expect(result.parsed.longitude).to eq(BigDecimal("116.06432"))
    expect(result.parsed.fingerprint).to be_present
  end

  it "uses the final paired data coordinates" do
    extended_url = "#{url}!3d5.98001!4d116.07002"

    parsed = described_class.call(extended_url).parsed

    expect(parsed.latitude).to eq(BigDecimal("5.98001"))
    expect(parsed.longitude).to eq(BigDecimal("116.07002"))
  end

  it "falls back to view coordinates" do
    fallback_url = "https://google.com/maps/place/Signal+Hill/@5.99211,116.08122,15z"

    parsed = described_class.call(fallback_url).parsed

    expect(parsed.latitude).to eq(BigDecimal("5.99211"))
    expect(parsed.longitude).to eq(BigDecimal("116.08122"))
  end

  it "decodes an encoded place name" do
    encoded_url = "https://maps.google.com/maps/place/Mari+Mari%20Cultural%20Village/@6.034,116.167,15z"

    expect(described_class.call(encoded_url).parsed.name).to eq("Mari Mari Cultural Village")
  end

  it "rejects an unapproved domain" do
    invalid = described_class.call("https://google.com.example/maps/place/Place/@5.9,116.0,15z")

    expect(invalid).not_to be_success
    expect(invalid.error).to eq("Enter a full Google Maps browser URL.")
  end

  it "rejects a short Google Maps link" do
    invalid = described_class.call("https://maps.app.goo.gl/example")

    expect(invalid).not_to be_success
  end

  it "rejects a URL without a place name" do
    invalid = described_class.call("https://www.google.com/maps/@5.9,116.0,15z")

    expect(invalid.error).to eq("The Google Maps URL does not contain a place name.")
  end

  it "rejects a URL without coordinates" do
    invalid = described_class.call("https://www.google.com/maps/place/Signal+Hill")

    expect(invalid.error).to eq("The Google Maps URL does not contain valid coordinates.")
  end

  it "rejects coordinates outside the valid range" do
    invalid = described_class.call("https://www.google.com/maps/place/Signal+Hill/@95,116,15z")

    expect(invalid.error).to eq("The latitude must be between -90 and 90.")
  end
end
