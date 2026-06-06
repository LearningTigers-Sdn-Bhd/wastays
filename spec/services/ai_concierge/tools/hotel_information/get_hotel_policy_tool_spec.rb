require "rails_helper"

RSpec.describe AiConcierge::Tools::HotelInformation::GetHotelPolicyTool do
  before do
    allow_any_instance_of(HotelKnowledges::SearchService).to receive(:call).and_return([])
  end

  it "returns hotel policy text from knowledge documents with property policy fallback" do
    hotel = create(:hotel, :with_ai_concierge)
    doc = create(:hotel_knowledge_document, hotel: hotel, category: "policy", title: "Pets", embedding_status: "indexed")
    create(:hotel_knowledge_chunk, document: doc, chunk_index: 0,
           content: "Pets are not allowed.")
    create(:property_policy, hotel: hotel, check_in_time: "15:00", check_out_time: "12:00",
           cancellation_policy: "24 hours")

    result = described_class.new(hotel: hotel, policy_topic: "hotel_policy").call

    expect(result).to include(
      "success" => true,
      "answer" => "Pets\nPets are not allowed.",
      "answer_mode" => "fallback",
      "policy_text" => "Pets\nPets are not allowed.",
      "check_in_time" => "15:00",
      "check_out_time" => "12:00",
      "cancellation_policy" => "24 hours",
      "source" => "hotel_policy"
    )
  end

  it "joins multiple policy documents" do
    hotel = create(:hotel, :with_ai_concierge)
    doc1 = create(:hotel_knowledge_document, hotel: hotel, category: "policy", title: "Pets", embedding_status: "indexed")
    create(:hotel_knowledge_chunk, document: doc1, chunk_index: 0,
           content: "Pets are not allowed.")
    doc2 = create(:hotel_knowledge_document, hotel: hotel, category: "policy", title: "Smoking", embedding_status: "indexed")
    create(:hotel_knowledge_chunk, document: doc2, chunk_index: 0,
           content: "Smoking is not allowed in the rooms.")

    result = described_class.new(hotel: hotel, policy_topic: "hotel_policy", query: "hotel policy").call

    expect(result["policy_text"]).to eq([
      "Pets",
      "Pets are not allowed.",
      "",
      "Smoking",
      "Smoking is not allowed in the rooms."
    ].join("\n"))
  end

  it "falls back to structured property policy when no knowledge documents exist" do
    hotel = create(:hotel, :with_ai_concierge)
    create(:property_policy, hotel: hotel, check_in_time: "15:00", check_out_time: "12:00",
           cancellation_policy: "24 hours")

    result = described_class.new(hotel: hotel, policy_topic: "hotel_policy", query: "what time is check in?").call

    expect(result).to include(
      "success" => true,
      "answer" => "Check-in starts at 15:00.",
      "answer_mode" => "fallback",
      "policy_text" => nil,
      "check_in_time" => "15:00",
      "check_out_time" => "12:00",
      "cancellation_policy" => "24 hours",
      "source" => "property_policy"
    )
  end

  it "returns an unavailable payload when both are missing" do
    hotel = create(:hotel, :with_ai_concierge)

    result = described_class.new(hotel: hotel, policy_topic: "hotel_policy").call

    expect(result).to include(
      "success" => false,
      "answer_mode" => "unavailable",
      "policy_text" => nil,
      "check_in_time" => nil,
      "check_out_time" => nil,
      "cancellation_policy" => nil,
      "source" => "property_policy"
    )
  end

  it "ignores documents without chunks" do
    hotel = create(:hotel, :with_ai_concierge)
    create(:hotel_knowledge_document, hotel: hotel, category: "policy", title: "Empty", embedding_status: "indexed")

    result = described_class.new(hotel: hotel, policy_topic: "hotel_policy").call

    expect(result).to include(
      "success" => false,
      "policy_text" => nil,
      "source" => "property_policy"
    )
  end
end
