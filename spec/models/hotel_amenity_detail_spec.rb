require "rails_helper"

RSpec.describe HotelAmenityDetail, type: :model do
  it "accepts a hotel amenity selected by the hotel" do
    detail = create(:hotel_amenity_detail)
    detail.hotel.update!(amenities: [ detail.amenity.slug ])

    expect(detail).to be_available
  end

  it "rejects room amenities" do
    detail = build(:hotel_amenity_detail, amenity: create(:amenity, :room))

    expect(detail).not_to be_valid
    expect(detail.errors[:amenity]).to include("must be a hotel amenity")
  end

  it "keeps details but does not expose them after deselection" do
    detail = create(:hotel_amenity_detail)
    detail.hotel.update!(amenities: [])

    expect(detail.reload).to be_persisted
    expect(detail).not_to be_available
  end

  it "allows only one detail per hotel amenity" do
    detail = create(:hotel_amenity_detail)

    expect(build(:hotel_amenity_detail, hotel: detail.hotel, amenity: detail.amenity)).not_to be_valid
  end
end
