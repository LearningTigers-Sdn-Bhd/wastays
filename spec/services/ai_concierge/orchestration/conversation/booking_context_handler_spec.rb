require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Conversation::BookingContextHandler do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel, phone_number: "+60123456789") }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect) }
  let(:tool_registry) { instance_double(AiConcierge::Tools::ToolRegistry) }

  it "fetches booking context using the explicit phone when present" do
    tool = booking_context_tool(expected_phone: "+60999999999")
    allow(tool_registry).to receive(:fetch).with("get_booking_context").and_return(tool)

    result = described_class.new(hotel: hotel, phone: "+60999999999", tool_registry: tool_registry).call(
      prospect: prospect,
      conversation_state: conversation_state
    )

    expect(result[:reply_type]).to eq(:booking_context)
    expect(result[:extra_context][:success]).to be(true)
    expect(result[:slots_payload]).to eq(conversation_state.slots_payload)
  end

  it "falls back to prospect phone when explicit phone is absent" do
    tool = booking_context_tool(expected_phone: prospect.phone_number)
    allow(tool_registry).to receive(:fetch).with("get_booking_context").and_return(tool)

    described_class.new(hotel: hotel, phone: nil, tool_registry: tool_registry).call(
      prospect: prospect,
      conversation_state: conversation_state
    )
  end

  def booking_context_tool(expected_phone:)
    Class.new do
      define_method(:initialize) do |hotel:, phone:|
        raise "unexpected hotel" unless hotel
        raise "unexpected phone #{phone}" unless phone == expected_phone
      end

      def call
        { "success" => true, "bookings" => [] }
      end
    end
  end
end
