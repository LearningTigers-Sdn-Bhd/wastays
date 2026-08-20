require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Turn::BookingContextHandler do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel, phone_number: "+60123456789") }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect) }

  it "fetches booking context using the explicit phone when present" do
    expect_booking_context_phone("+60999999999")

    result = described_class.new(hotel: hotel, phone: "+60999999999").call(
      prospect: prospect,
      conversation_state: conversation_state
    )

    expect(result[:reply_type]).to eq(:booking_context)
    expect(result[:extra_context][:success]).to be(true)
    expect(result[:slots_payload]).to eq(conversation_state.slots_payload)
  end

  it "falls back to prospect phone when explicit phone is absent" do
    expect_booking_context_phone(prospect.phone_number)

    described_class.new(hotel: hotel, phone: nil).call(
      prospect: prospect,
      conversation_state: conversation_state
    )
  end

  # Nothing exercised this handler's result all the way to the persister, so
  # the shape it returns was free to drift from every other turn's and the
  # suite stayed green. It reaches a guest through
  # `Tools::Llm::GetBookingContextTool` -> `ToolRecorder` -> `TurnOrchestrator`,
  # and that is the path this walks.
  it "returns a result the persister can write" do
    conversation = create(:conversation, :whatsapp, hotel: hotel, prospect: prospect)
    result = described_class.new(hotel: hotel, phone: prospect.phone_number).call(
      prospect: prospect,
      conversation_state: conversation_state
    )

    payload = AiConcierge::Orchestration::Turn::ResponsePersister
      .new(hotel: hotel, conversation: conversation)
      .persist_domain_response(prospect: prospect, conversation_state: conversation_state, domain_result: result)

    expect(payload[:reply_message]).to be_present
  end

  def expect_booking_context_phone(expected)
    klass = AiConcierge::Tools::HotelInformation::GetBookingContextTool
    allow(klass).to receive(:new) do |phone:, **|
      raise "unexpected phone #{phone}" unless phone == expected

      instance_double(klass, call: { "success" => true, "bookings" => [] })
    end
  end
end
