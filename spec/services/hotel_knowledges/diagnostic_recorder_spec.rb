# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelKnowledges::DiagnosticRecorder do
  let(:hotel) { create(:hotel) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let!(:message) { create(:prospect_message, prospect: prospect, direction: "inbound", body: "Do you provide airport pickup?") }

  it "creates a diagnostic for unavailable answers" do
    result = record(
      tool_result: {
        "success" => false,
        "answer_mode" => "unavailable",
        "answer" => "The hotel has not provided that information yet.",
        "source" => "general_hotel_info",
        "knowledge_matches" => [],
        "searched_categories" => [ "general_info" ],
        "fallback_categories" => [ "general_info", "faq", "policy" ]
      }
    )

    expect(result).to be_persisted
    expect(result.prospect).to eq(prospect)
    expect(result.prospect_message).to eq(message)
    expect(result.suggested_category).to eq("general_info")
    expect(result.routed_categories).to eq([ "general_info" ])
    expect(result.fallback_categories).to eq([ "general_info", "faq", "policy" ])
  end

  it "creates a diagnostic for weak vector matches" do
    result = record(
      tool_result: {
        "success" => true,
        "answer_mode" => "synthesized",
        "answer" => "Airport pickup may be available.",
        "source" => "general_hotel_info",
        "knowledge_matches" => [
          { "content" => "Airport transfer information.", "document_title" => "Transport", "category" => "general_info", "distance" => 0.78 }
        ],
        "searched_categories" => [ "general_info" ]
      }
    )

    expect(result).to be_persisted
    expect(result.match_count).to eq(1)
    expect(result.best_distance).to eq(0.78)
  end

  it "does not create a diagnostic for strong deterministic answers" do
    expect {
      record(
        tool_result: {
          "success" => true,
          "answer_mode" => "deterministic",
          "answer" => "Parking is complimentary.",
          "source" => "hotel_faq",
          "knowledge_matches" => [
            { "content" => "Parking is complimentary.", "document_title" => "Parking", "category" => "faq", "distance" => 0.12 }
          ],
          "searched_categories" => [ "faq" ]
        }
      )
    }.not_to change(HotelKnowledgeDiagnostic, :count)
  end

  it "tolerates malformed tool results" do
    expect {
      record(tool_result: "bad")
    }.not_to raise_error
  end

  def record(tool_result:)
    described_class.new(
      hotel: hotel,
      question: "Do you provide airport pickup?",
      intent: "hotel_information",
      topic: "general_hotel_info",
      tool_result: tool_result,
      prospect: prospect
    ).call
  end
end
