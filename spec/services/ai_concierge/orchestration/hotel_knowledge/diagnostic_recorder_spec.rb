require "rails_helper"

RSpec.describe AiConcierge::Orchestration::HotelKnowledge::DiagnosticRecorder do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel, phone_number: "+60123456789") }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect) }
  let(:recorder) { instance_double(HotelKnowledges::DiagnosticRecorder, call: true) }

  it "delegates diagnostic recording with conversation context" do
    allow(HotelKnowledges::DiagnosticRecorder).to receive(:new).and_return(recorder)
    result = { "success" => false, "answer_mode" => "unavailable" }
    interpretation = { "intent" => "hotel_information", "topic" => "general_hotel_info" }

    described_class.new(
      hotel: hotel,
      message: "do you have parking?",
      interpretation: interpretation,
      conversation_state: conversation_state,
      result: result
    ).call

    expect(HotelKnowledges::DiagnosticRecorder).to have_received(:new).with(
      hotel: hotel,
      question: "do you have parking?",
      intent: "hotel_information",
      topic: "general_hotel_info",
      tool_result: result,
      prospect: prospect
    )
    expect(recorder).to have_received(:call)
  end
end
