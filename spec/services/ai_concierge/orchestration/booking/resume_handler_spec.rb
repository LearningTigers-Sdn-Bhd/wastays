require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Booking::ResumeHandler do
  let(:conversation_state) { build_stubbed(:prospect_conversation_state, slots_payload: slots_payload) }
  let(:slots_payload) do
    active_payload = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(active_branch, pending_question: "confirm_selection")

    AiConcierge::State::ConversationTaskManager.new(slots_payload: active_payload).suspend_booking_for_information(
      intent: "hotel_policy",
      topic: "hotel_information",
      pending_question: "confirm_selection"
    )
  end
  let(:active_branch) do
    {
      "target_month" => 8,
      "target_year" => 2026,
      "month_segment" => "early",
      "adults" => 2,
      "children" => 1,
      "suggested_options" => [ { "room_type_name" => "Garden Suite", "options" => [ option ] } ],
      "confirmation_candidate" => option
    }
  end
  let(:option) do
    {
      "selection_id" => "garden_1",
      "check_in" => "2026-08-01",
      "check_out" => "2026-08-02"
    }
  end
  let(:domain_response) { ->(**args) { args } }

  it "returns to option selection when a resumed confirmation is declined" do
    result = handler(
      interpretation: { "intent" => "confirmation", "slots" => { "confirmation" => "no" } }
    ).call

    expect(result[:reply_type]).to eq(:suggest_options)
    expect(result[:pending_question]).to eq("select_option")
    expect(result.dig(:extra_context, :month_label)).to eq("early August 2026")
    expect(result.dig(:extra_context, :guest_label)).to eq("2 adults and 1 child")
  end

  it "delegates accepted confirmation to the completion handler" do
    completion_handler = instance_double(AiConcierge::Orchestration::Booking::CompletionHandler)
    allow(completion_handler).to receive(:call).and_return({ reply_type: :booking_link_ready })

    result = handler(
      interpretation: { "intent" => "confirmation", "slots" => { "confirmation" => "yes" } },
      completion_handler: completion_handler
    ).call

    expect(result[:reply_type]).to eq(:booking_link_ready)
    expect(completion_handler).to have_received(:call).with(conversation_state: conversation_state, active_branch: hash_including("confirmation_candidate" => option))
  end

  it "resumes visible options when no selection-like message was sent" do
    result = handler(interpretation: { "intent" => "greeting", "slots" => {} }).call

    expect(result[:reply_type]).to eq(:resume_options)
    expect(result[:pending_question]).to eq("select_option")
    expect(result.dig(:extra_context, :search_params, "check_in")).to eq("2026-08-01")
  end

  def handler(interpretation:, completion_handler: instance_double(AiConcierge::Orchestration::Booking::CompletionHandler, call: { reply_type: :booking_link_ready }))
    described_class.new(
      conversation_state: conversation_state,
      interpretation: interpretation,
      active_branch: active_branch.deep_dup,
      message: "hello",
      selection_handler: instance_double(AiConcierge::Orchestration::Booking::SelectionHandler),
      completion_handler: completion_handler,
      action_resolver: instance_double(AiConcierge::Orchestration::Booking::ActionResolver),
      process_booking_action: ->(*) { { reply_type: :processed } },
      handle_booking_revision: ->(**) { },
      handle_search_options: ->(**) { { reply_type: :search_options } },
      domain_response: domain_response
    )
  end
end
