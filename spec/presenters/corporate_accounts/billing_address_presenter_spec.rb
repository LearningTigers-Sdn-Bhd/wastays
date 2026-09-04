# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporateAccounts::BillingAddressPresenter do
  it "formats a complete relationship address" do
    relationship = build(:hotel_corporate_account,
      billing_address_line1: "Level 3, Lot 8",
      billing_address_line2: "Jalan Lintas",
      billing_city: "Kota Kinabalu",
      billing_state: "Sabah",
      billing_postal_code: "88300",
      billing_country: "Malaysia")

    presenter = described_class.new(relationship)

    expect(presenter).to be_complete
    expect(presenter.status_label).to eq("Billing address complete")
    expect(presenter.lines).to eq([ "Level 3, Lot 8", "Jalan Lintas", "88300 Kota Kinabalu", "Sabah, Malaysia" ])
  end

  it "distinguishes missing and incomplete addresses" do
    missing = described_class.new({})
    incomplete = described_class.new("address_line1" => "Lot 8")

    expect(missing).to be_missing
    expect(missing.status_label).to eq("Billing address missing")
    expect(incomplete).to be_incomplete
    expect(incomplete.status_label).to eq("Billing address incomplete")
  end

  it "serializes the complete address shape for invoice snapshots" do
    presenter = described_class.new(address_line1: "Lot 8", city: "Kuching", country: "Malaysia")

    expect(presenter.snapshot).to eq(
      "address_line1" => "Lot 8",
      "address_line2" => nil,
      "city" => "Kuching",
      "state" => nil,
      "postal_code" => nil,
      "country" => "Malaysia"
    )
  end

  it "preserves long international address values for PDF wrapping" do
    presenter = described_class.new(
      address_line1: "東京都千代田区丸の内一丁目の長いビル名 18階 Corporate Accounts Department",
      address_line2: "Attn: Regional Travel and Procurement Operations",
      city: "東京都千代田区",
      state: "東京都",
      postal_code: "100-0005",
      country: "日本"
    )

    expect(presenter).to be_complete
    expect(presenter.lines).to eq([
      "東京都千代田区丸の内一丁目の長いビル名 18階 Corporate Accounts Department",
      "Attn: Regional Travel and Procurement Operations",
      "100-0005 東京都千代田区",
      "東京都, 日本"
    ])
  end
end
