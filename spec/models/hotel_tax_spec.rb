# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelTax, type: :model do
  it { is_expected.to belong_to(:hotel) }
  it { is_expected.to belong_to(:transaction_code).optional }

  it "creates a custom tax transaction code after create" do
    hotel = create(:hotel)

    tax = create(:hotel_tax, hotel: hotel, name: "Dewan Bandaraya Kota Kinabalu", code: "DBKK", rate_type: "flat", amount: 10)

    expect(tax.code).to eq("DBKK")
    expect(tax.transaction_code).to be_present
    expect(tax.transaction_code.system_key).to eq("hotel_tax_#{tax.id}")
    expect(tax.transaction_code.code).to eq("TAX_DBKK")
    expect(tax.transaction_code.name).to eq("Dewan Bandaraya Kota Kinabalu")
    expect(tax.transaction_code.kind).to eq("tax")
  end

  it "normalizes spaces in tax code to underscores" do
    tax = create(:hotel_tax, name: "Local Council Tax", code: "dewan bandaraya")

    expect(tax.code).to eq("DEWAN_BANDARAYA")
    expect(tax.transaction_code.code).to eq("TAX_DEWAN_BANDARAYA")
  end

  it "falls back to a name abbreviation when tax code is blank" do
    tax = create(:hotel_tax, name: "Dewan Bandaraya Kota Kinabalu", code: "")

    expect(tax.code).to eq("DBKK")
    expect(tax.transaction_code.code).to eq("TAX_DBKK")
  end

  it "syncs transaction code when tax code or name changes" do
    tax = create(:hotel_tax, name: "Service Charge", code: "SC")

    tax.update!(name: "Local Council Tax", code: "LCT")

    expect(tax.transaction_code.reload.name).to eq("Local Council Tax")
    expect(tax.transaction_code.code).to eq("TAX_LCT")
  end

  it "creates disabled tax transaction codes as inactive" do
    hotel = create(:hotel)

    tax = create(:hotel_tax, hotel: hotel, name: "Service Charge", enabled: false)

    expect(tax.transaction_code).not_to be_active
  end

  it "syncs transaction code active state when enabled changes" do
    tax = create(:hotel_tax, enabled: true)

    expect {
      tax.update!(enabled: false)
    }.to change { tax.transaction_code.reload.active? }.from(true).to(false)

    expect {
      tax.update!(enabled: true)
    }.to change { tax.transaction_code.reload.active? }.from(false).to(true)
  end

  it "suffixes duplicate custom tax transaction code abbreviations" do
    hotel = create(:hotel)

    first_tax = create(:hotel_tax, hotel: hotel, name: "City Council Fee", code: "CCF", amount: 5)
    second_tax = create(:hotel_tax, hotel: hotel, name: "Custom Cleaning Fee", code: "CCF", amount: 6)

    expect(first_tax.transaction_code.code).to eq("TAX_CCF")
    expect(second_tax.code).to eq("CCF2")
    expect(second_tax.transaction_code.code).to eq("TAX_CCF2")
  end

  it "suffixes manual codes that collide with default tax transaction codes" do
    tax = create(:hotel_tax, code: "SST")

    expect(tax.code).to eq("SST2")
    expect(tax.transaction_code.code).to eq("TAX_SST2")
  end
end
