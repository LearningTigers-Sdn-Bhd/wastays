require "rails_helper"

RSpec.describe HotelPortal::Amenities::UpdateSelection, type: :service do
  let(:hotel) { create(:hotel) }

  it "replaces the selected amenities and drops blanks" do
    result = described_class.call(hotel: hotel, slugs: [ "", "swimming_pool", "fitness_center", "swimming_pool" ])

    expect(result).to be_success
    expect(hotel.reload.amenities).to contain_exactly("swimming_pool", "fitness_center")
  end

  it "keeps the guest details of an amenity that leaves the selection" do
    amenity = Amenity.hotel.find_by!(slug: "swimming_pool")
    hotel.update!(amenities: [ amenity.slug ])
    create(:hotel_amenity_detail, hotel: hotel, amenity: amenity, location: "Rooftop")

    described_class.call(hotel: hotel, slugs: [ "fitness_center" ])

    expect(hotel.hotel_amenity_details.find_by(amenity: amenity).location).to eq("Rooftop")
  end

  it "rejects a slug that is not in the amenity catalog" do
    result = described_class.call(hotel: hotel, slugs: [ "helipad_and_submarine_dock" ])

    expect(result).not_to be_success
    expect(result.hotel.errors[:amenities]).to be_present
  end
end
