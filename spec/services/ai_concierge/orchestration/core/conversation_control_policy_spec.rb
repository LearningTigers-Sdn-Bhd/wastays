require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Core::ConversationControlPolicy do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:interpretation) do
    {
      "intent" => "greeting",
      "slots" => {},
      "conversation_signals" => {}
    }
  end

  def state(active_flow: nil, pending_question: nil, slots_payload: {})
      create(
        :prospect_conversation_state,
        prospect: create(:prospect, hotel: hotel),
      active_flow: active_flow,
      pending_question: pending_question,
      slots_payload: slots_payload
    )
  end

  def policy(message:, conversation_state:, current_interpretation: interpretation)
    described_class.new(message: message, conversation_state: conversation_state, interpretation: current_interpretation)
  end

  it "detects explicit end requests" do
    control = policy(message: "end conversation", conversation_state: state)

    expect(control).to be_explicit_end
  end

  it "detects explicit booking-attempt cancellation" do
    control = policy(message: "cancel my booking attempt", conversation_state: state)

    expect(control).to be_cancel_attempt
  end

  it "does not treat an existing-booking cancellation as an attempt cancellation" do
    control = policy(message: "cancel my booking", conversation_state: state(active_flow: "booking_search"))

    expect(control).not_to be_cancel_attempt
  end

  it "detects Malay and Chinese booking-attempt cancellation wording" do
    expect(policy(message: "Batalkan percubaan tempahan", conversation_state: state)).to be_cancel_attempt
    expect(policy(message: "取消预订尝试", conversation_state: state)).to be_cancel_attempt
  end

  it "detects n8n wait-time end control messages" do
    control = policy(message: "codename: wait-time-end", conversation_state: state)

    expect(control).to be_wait_time_end
  end

  it "only treats natural abandonment as cancellation during an active booking" do
    inactive = policy(message: "changed my mind", conversation_state: state)
    active = policy(message: "changed my mind", conversation_state: state(active_flow: "booking_search"))

    expect(inactive).not_to be_cancel_attempt
    expect(active).to be_cancel_attempt
  end

  it "detects booking progress from active booking state" do
    inactive = policy(message: "codename: wait-time-end", conversation_state: state)
    active = policy(message: "codename: wait-time-end", conversation_state: state(active_flow: "booking_search"))

    expect(inactive).not_to be_booking_progress
    expect(active).to be_booking_progress
  end

  it "detects positive end confirmation responses" do
    yes = interpretation.merge("intent" => "confirmation", "slots" => { "confirmation" => "yes" })

    expect(policy(message: "yes", conversation_state: state, current_interpretation: yes)).to be_end_confirmation_yes
  end

  it "returns end confirmation mode for active booking and suspended booking states" do
    active = policy(message: "stop", conversation_state: state(active_flow: "booking_search"))
    suspended_payload = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(
      AiConcierge::State::SlotMerger.empty_branch.merge("target_month" => 8),
      pending_question: "select_option",
      status: "suspended"
    )
    suspended = policy(message: "stop", conversation_state: state(slots_payload: suspended_payload))

    expect(active.end_confirmation_mode).to eq(:cancel_booking_attempt)
    expect(suspended.end_confirmation_mode).to eq(:continue_booking)
  end
end
