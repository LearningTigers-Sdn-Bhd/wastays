require "rails_helper"

RSpec.describe HotelPortal::GuestContent::AmenityRow do
  let(:amenity) { Amenity.hotel.find_by!(slug: "swimming_pool") }

  it "reads Not started when no detail row exists" do
    row = described_class.new(amenity: amenity)

    expect(row.status_label).to eq("Not started")
    expect(row.status_variant).to eq(:neutral)
  end

  it "reads Not started when the saved row holds no guest content" do
    row = described_class.new(amenity: amenity, detail: HotelAmenityDetail.new)

    expect(row.status_label).to eq("Not started")
  end

  it "reads Incomplete when some content fields are blank" do
    row = described_class.new(amenity: amenity, detail: HotelAmenityDetail.new(location: "Rooftop"))

    expect(row.status_label).to eq("Incomplete")
    expect(row.status_variant).to eq(:warning)
  end

  it "reads Ready when every content field is filled" do
    detail = HotelAmenityDetail.new(location: "Rooftop", opening_hours: "8 AM to 8 PM", fee_information: "Free")
    row = described_class.new(amenity: amenity, detail: detail)

    expect(row.status_label).to eq("Ready")
    expect(row.status_variant).to eq(:success)
  end

  it "pairs each amenity with its own detail row" do
    hotel = create(:hotel)
    other = Amenity.hotel.find_by!(slug: "fitness_center")
    create(:hotel_amenity_detail, hotel: hotel, amenity: amenity, location: "Rooftop")

    rows = described_class.build(hotel: hotel, amenities: [ amenity, other ])

    expect(rows.map(&:location)).to eq([ "Rooftop", nil ])
  end
end
