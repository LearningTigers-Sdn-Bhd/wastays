# frozen_string_literal: true

require "rails_helper"

RSpec.describe PostalAddresses::Presenter do
  it "formats a multiline Malaysian address and translates its state code" do
    presenter = described_class.from_booking(
      build(:booking,
        guest_home_address: "Unit 8\nNo. 12, Jalan Ampang",
        guest_city: "Kuala Lumpur",
        guest_state_code: "14",
        guest_postal_code: "50450",
        guest_address_country: "Malaysia")
    )

    expect(presenter.lines).to eq([
      "Unit 8",
      "No. 12, Jalan Ampang",
      "50450 Kuala Lumpur",
      "Wilayah Persekutuan Kuala Lumpur, Malaysia"
    ])
    expect(presenter.status_label).to eq("Address complete")
  end

  it "omits the LHDN not-applicable state from foreign postal addresses" do
    presenter = described_class.new(
      address_line1: "1 Orchard Road",
      city: "Singapore",
      state: PostalAddresses::Presenter.printable_state("17"),
      postal_code: "238823",
      country: "Singapore"
    )

    expect(presenter.display).to eq("1 Orchard Road\n238823 Singapore\nSingapore")
  end

  it "reports missing, incomplete, and complete addresses" do
    expect(described_class.new.status_label).to eq("Address missing")
    expect(described_class.new(address_line1: "Lot 8").status_label).to eq("Address incomplete")
    expect(described_class.new(address_line1: "Lot 8", city: "Kuching", country: "Malaysia").status_label).to eq("Address complete")
  end
end
