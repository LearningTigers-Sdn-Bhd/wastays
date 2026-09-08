# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelTransportDetail, type: :model do
  let(:hotel) { create(:hotel) }

  it "keeps one record per hotel" do
    create(:hotel_transport_detail, hotel: hotel)
    duplicate = build(:hotel_transport_detail, hotel: hotel)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:hotel_id]).to be_present
  end

  it "rejects a parking availability that is not on the list" do
    detail = build(:hotel_transport_detail, parking_availability: "maybe")

    expect(detail).not_to be_valid
    expect(detail.errors[:parking_availability]).to be_present
  end

  it "rejects a negative price and a height limit of zero" do
    detail = build(:hotel_transport_detail, parking_price: -5, parking_height_limit_m: 0)

    expect(detail).not_to be_valid
    expect(detail.errors[:parking_price]).to be_present
    expect(detail.errors[:parking_height_limit_m]).to be_present
  end

  it "accepts a record with no numbers, because a hotel fills the page over time" do
    expect(build(:hotel_transport_detail, airport_distance_km: nil, airport_travel_minutes: nil)).to be_valid
  end

  describe "readiness" do
    it "reports no parking until the hotel says it has some" do
      expect(build(:hotel_transport_detail)).not_to be_parking
      expect(build(:hotel_transport_detail, :with_parking)).to be_parking
    end

    it "reports transportation as filled once the hotel offers a transfer" do
      expect(build(:hotel_transport_detail)).not_to be_transportation_present
      expect(build(:hotel_transport_detail, :with_transfer)).to be_transportation_present
    end

    it "reports transportation as filled from a public transport stop alone" do
      detail = build(:hotel_transport_detail, nearest_transit_stop: "KL Sentral")

      expect(detail).to be_transportation_present
    end

    it "reports directions as filled from any one distance or the written text" do
      expect(build(:hotel_transport_detail)).to be_directions_present
      expect(build(:hotel_transport_detail, airport_distance_km: nil, airport_travel_minutes: nil,
        directions: nil)).not_to be_directions_present
    end
  end

  describe "labels" do
    it "names the parking option, the parking type, and the price unit" do
      detail = build(:hotel_transport_detail, :with_parking)

      expect(detail.parking_label).to eq("On-site")
      expect(detail.parking_type_label).to eq("Valet")
      expect(detail.price_unit_label).to eq("Per night")
    end
  end

  describe "sections" do
    it "gives each sheet its own columns, and no column to two sheets" do
      columns = described_class::SECTION_ATTRIBUTES.values.flatten

      expect(described_class::SECTIONS).to eq(%w[directions transportation parking])
      expect(columns).to eq(columns.uniq)
    end
  end
end
