require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Booking::CompletionHandler do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel, phone_number: "+60123456789") }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect, slots_payload: {}) }
  let(:selected_option) do
    {
      "selection_id" => "garden_1",
      "selected_rate_plan" => { "rate_plan_id" => 10, "name" => "Standard Rate" }
    }
  end

  it "generates a booking link and archives the completed booking task" do
    klass = AiConcierge::Tools::Booking::GenerateBookingUrlTool
    allow(klass).to receive(:new) do |guest_phone:, rate_plan_id:, **|
      instance_double(klass, call: { "success" => true, "booking_url" => "https://example.test/book", "guest_phone" => guest_phone, "rate_plan_id" => rate_plan_id })
    end
    active_branch = { "confirmation_candidate" => selected_option }

    result = described_class.new(
      hotel: hotel,
      prospect: prospect,
      phone: nil,
    ).call(conversation_state: conversation_state, active_branch: active_branch)

    expect(result[:reply_type]).to eq(:booking_link_ready)
    expect(result[:flow_status]).to eq("ended")
    expect(result[:end_reason]).to eq("booking_url_generated")
    expect(result.dig(:extra_context, :result, "guest_phone")).to eq(prospect.phone_number)
    expect(result.dig(:extra_context, :result, "rate_plan_id")).to eq(10)
    expect(result.dig(:slots_payload, "booking_task", "status")).to eq("idle")
    expect(result.dig(:slots_payload, "completed_booking_branches").last["selected_option"]["selection_id"]).to eq("garden_1")
  end

  # This class was the one copy of `booking_response` that never passed
  # `count_reask: true`, so a guest looping here advanced no counter and
  # `Orchestrator#escalate` -- which reads it -- could never nudge them or ask
  # for a person. Nothing said whether that was a decision or a slip.
  it "counts a re-ask so a guest looping here can reach a person" do
    branch = AiConcierge::State::SlotMerger.empty_branch
    conversation_state.update!(
      slots_payload: AiConcierge::State::ConversationTaskManager
        .new(slots_payload: {})
        .activate_booking(branch, pending_question: "select_option")
    )
    handler = described_class.new(hotel: hotel, prospect: prospect, phone: nil)

    first = handler.call(conversation_state: conversation_state, active_branch: branch)
    expect(first[:reply_type]).to eq(:invalid_selection)
    expect(first.dig(:slots_payload, "booking_task", "reask_count")).to eq(1)

    conversation_state.update!(slots_payload: first.slots_payload)
    second = handler.call(conversation_state: conversation_state, active_branch: branch)
    expect(second.dig(:slots_payload, "booking_task", "reask_count")).to eq(2)
  end

  it "asks the guest to select an option when nothing is selected" do
    result = described_class.new(
      hotel: hotel,
      prospect: prospect,
      phone: prospect.phone_number
    ).call(conversation_state: conversation_state, active_branch: {})

    expect(result[:reply_type]).to eq(:invalid_selection)
    expect(result[:pending_question]).to eq("select_option")
    expect(result[:active_flow]).to eq("booking_search")
  end
end
