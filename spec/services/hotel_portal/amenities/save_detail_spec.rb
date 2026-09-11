require "rails_helper"

RSpec.describe HotelPortal::Amenities::SaveDetail, type: :service do
  let(:hotel) { create(:hotel) }
  let(:amenity) { Amenity.hotel.find_by!(slug: "swimming_pool") }

  before { hotel.update!(amenities: [ amenity.slug ]) }

  it "creates the detail row on the first save" do
    result = described_class.call(
      hotel: hotel,
      amenity: amenity,
      attributes: { location: "Rooftop", opening_hours: "8 AM to 8 PM" }
    )

    expect(result).to be_success
    expect(hotel.hotel_amenity_details.find_by!(amenity: amenity).location).to eq("Rooftop")
  end

  it "updates the existing row and ignores unpermitted attributes" do
    detail = create(:hotel_amenity_detail, hotel: hotel, amenity: amenity, location: "Level 2")
    other_hotel = create(:hotel)

    described_class.call(
      hotel: hotel,
      amenity: amenity,
      attributes: { location: "Level 3", hotel_id: other_hotel.id }
    )

    expect(detail.reload.location).to eq("Level 3")
    expect(detail.hotel_id).to eq(hotel.id)
  end
end
