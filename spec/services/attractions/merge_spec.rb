# frozen_string_literal: true

require "rails_helper"

RSpec.describe Attractions::Merge do
  let(:source) { create(:attraction, :pending) }
  let(:target) { create(:attraction) }

  it "moves hotel links and archives the source" do
    source_only_hotel = create(:hotel)
    shared_hotel = create(:hotel)
    create(:hotel_nearby_attraction, hotel: source_only_hotel, attraction: source, description: "Source text")
    create(:hotel_nearby_attraction, hotel: shared_hotel, attraction: source, description: "Source text")
    target_link = create(:hotel_nearby_attraction, hotel: shared_hotel, attraction: target, description: "Target text")

    result = described_class.call(source: source, target: target)

    expect(result).to be_success
    expect(result.merged_links_count).to eq(2)
    expect(source.reload).to be_status_archived
    expect(source.merged_into).to eq(target)
    expect(source.hotel_nearby_attractions).to be_empty
    expect(target.hotel_nearby_attractions.find_by(hotel: source_only_hotel).description).to eq("Source text")
    expect(target_link.reload.description).to eq("Target text")
  end

  it "rejects a merge into an archived target" do
    target.update!(status: "archived", archived_from_status: "approved")

    result = described_class.call(source: source, target: target)

    expect(result).not_to be_success
  end
end
