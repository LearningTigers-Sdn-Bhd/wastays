require "rails_helper"

RSpec.describe AiConciergeV3::Orchestration::HotelKnowledge::RoomReplyResolver do
  it "maps successful room lookup to room details" do
    expect(described_class.new(result: { "success" => true }).call).to eq(:room_type_details)
  end

  it "maps ambiguous room lookup to an ambiguity reply" do
    expect(described_class.new(result: { "success" => false, "error" => "ambiguous_room_type" }).call).to eq(:ambiguous_room_type)
  end

  it "maps other failed room lookup results to not found" do
    expect(described_class.new(result: { "success" => false, "error" => "room_type_not_found" }).call).to eq(:room_type_not_found)
  end
end
