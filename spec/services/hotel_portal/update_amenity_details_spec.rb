require "rails_helper"

RSpec.describe HotelPortal::UpdateAmenityDetails, type: :service do
  it "saves details only for selected hotel amenities" do
    hotel = create(:hotel)
    selected = Amenity.hotel.find_by!(slug: "swimming_pool")
    unselected = Amenity.hotel.find_by!(slug: "fitness_center")
    hotel.update!(amenities: [ selected.slug ])

    result = described_class.new(hotel: hotel, rows: {
      selected.id.to_s => { "location" => "Roof" },
      unselected.id.to_s => { "location" => "Lobby" }
    }).call

    expect(result).to be true
    expect(hotel.hotel_amenity_details.find_by(amenity: selected).location).to eq("Roof")
    expect(hotel.hotel_amenity_details.find_by(amenity: unselected)).to be_nil
  end
end
