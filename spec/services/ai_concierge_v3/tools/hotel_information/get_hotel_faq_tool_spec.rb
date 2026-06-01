require "rails_helper"

RSpec.describe AiConciergeV3::Tools::HotelInformation::GetHotelFaqTool do
  before do
    allow_any_instance_of(HotelKnowledges::SearchService).to receive(:call).and_return([])
  end

  it "returns the full formatted faq from knowledge documents and chunks" do
    hotel = create(:hotel)
    doc = create(:hotel_knowledge_document, hotel: hotel, category: "faq", title: "General", embedding_status: "indexed")
    create(:hotel_knowledge_chunk, document: doc, chunk_index: 0,
           content: "Q: Do you offer airport transfers?\nA: Yes, on request.")
    create(:hotel_knowledge_chunk, document: doc, chunk_index: 1,
           content: "Q: What time is breakfast?\nA: Breakfast is served from 7 AM to 10 AM.")

    result = described_class.new(hotel: hotel).call

    expect(result).to include(
      "success" => true,
      "answer" => [
        "General",
        "Q: Do you offer airport transfers?\nA: Yes, on request.",
        "Q: What time is breakfast?\nA: Breakfast is served from 7 AM to 10 AM."
      ].join("\n"),
      "answer_mode" => "fallback",
      "faq_text" => [
        "General",
        "Q: Do you offer airport transfers?\nA: Yes, on request.",
        "Q: What time is breakfast?\nA: Breakfast is served from 7 AM to 10 AM."
      ].join("\n"),
      "source" => "hotel_faq",
      "knowledge_matches" => []
    )
  end

  it "joins multiple faq documents" do
    hotel = create(:hotel)
    doc1 = create(:hotel_knowledge_document, hotel: hotel, category: "faq", title: "General", embedding_status: "indexed")
    create(:hotel_knowledge_chunk, document: doc1, chunk_index: 0,
           content: "Q: Do you offer airport transfers?\nA: Yes.")
    doc2 = create(:hotel_knowledge_document, hotel: hotel, category: "faq", title: "Dining", embedding_status: "indexed")
    create(:hotel_knowledge_chunk, document: doc2, chunk_index: 0,
           content: "Q: Do you serve halal food?\nA: Selected options are available.")

    result = described_class.new(hotel: hotel).call

    expect(result["faq_text"]).to eq([
      "General",
      "Q: Do you offer airport transfers?\nA: Yes.",
      "",
      "Dining",
      "Q: Do you serve halal food?\nA: Selected options are available."
    ].join("\n"))
  end

  it "returns an unavailable payload when no faq documents exist" do
    hotel = create(:hotel)

    result = described_class.new(hotel: hotel).call

    expect(result).to include(
      "success" => false,
      "answer_mode" => "unavailable",
      "faq_text" => nil,
      "source" => "hotel_faq"
    )
  end

  it "returns an unavailable payload when documents have no chunks" do
    hotel = create(:hotel)
    create(:hotel_knowledge_document, hotel: hotel, category: "faq", title: "Empty", embedding_status: "indexed")

    result = described_class.new(hotel: hotel).call

    expect(result).to include(
      "success" => false,
      "answer_mode" => "unavailable",
      "faq_text" => nil,
      "source" => "hotel_faq"
    )
  end
end
