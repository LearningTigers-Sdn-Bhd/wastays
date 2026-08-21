require "rails_helper"

RSpec.describe AiConcierge::State::ConversationTaskManager do
  describe "counting a question the guest keeps not answering" do
    let(:branch) { { "branch_id" => "branch-1", "target_month" => 8, "target_year" => 2026 } }

    def asked(payload, question, branch, count_reask: true)
      described_class.new(slots_payload: payload).activate_booking(branch, pending_question: question, count_reask: count_reask)
    end

    it "counts the same question asked again over an unmoved branch" do
      first = asked({}, "rate_plan_selection", branch)
      second = asked(first, "rate_plan_selection", branch)
      third = asked(second, "rate_plan_selection", branch)

      expect(first.dig("booking_task", "reask_count")).to eq(0)
      expect(second.dig("booking_task", "reask_count")).to eq(1)
      expect(third.dig("booking_task", "reask_count")).to eq(2)
    end

    it "forgets the count when the branch moves" do
      first = asked({}, "rate_plan_selection", branch)
      second = asked(first, "rate_plan_selection", branch)
      moved = asked(second, "rate_plan_selection", branch.merge("selected_rate_plan_name" => "Standard Rate"))

      expect(second.dig("booking_task", "reask_count")).to eq(1)
      expect(moved.dig("booking_task", "reask_count")).to eq(0)
    end

    it "forgets the count when the question changes" do
      first = asked({}, "rate_plan_selection", branch)
      second = asked(first, "rate_plan_selection", branch)
      next_question = asked(second, "confirm_selection", branch)

      expect(next_question.dig("booking_task", "reask_count")).to eq(0)
    end

    # PrepareTurn re-activates the open question at the top of every turn.
    # Counting there would strike the guest for the hotel's own bookkeeping.
    it "does not count a caller that is only refreshing the task" do
      first = asked({}, "rate_plan_selection", branch)
      refreshed = asked(first, "rate_plan_selection", branch, count_reask: false)
      still_counted = asked(refreshed, "rate_plan_selection", branch)

      expect(refreshed.dig("booking_task", "reask_count")).to eq(0)
      expect(still_counted.dig("booking_task", "reask_count")).to eq(1)
    end
  end

  it "normalizes legacy active state into a v2 booking task" do
    branch = { "branch_id" => "branch-1", "target_month" => 8 }

    payload = described_class.new(slots_payload: { "active" => branch, "paused_flows" => [] }).payload

    expect(payload["state_version"]).to eq(2)
    expect(payload["booking_task"]["branch"]["target_month"]).to eq(8)
    expect(payload).not_to have_key("active")
    expect(payload).not_to have_key("paused_flows")
  end

  it "normalizes legacy paused booking flow into a suspended v2 booking task" do
    branch = { "branch_id" => "branch-1", "suggested_options" => [ { "room_type_name" => "Deluxe Room" } ] }
    payload = described_class.new(slots_payload: {
      "paused_flows" => [
        {
          "topic" => "booking_search",
          "pending_question" => "select_option",
          "slots" => branch,
          "updated_at" => Time.current.iso8601,
          "expires_at" => 30.minutes.from_now.iso8601
        }
      ]
    }).payload

    expect(payload.dig("booking_task", "status")).to eq("suspended")
    expect(payload.dig("booking_task", "pending_question")).to eq("select_option")
    expect(payload.dig("booking_task", "branch", "suggested_options")).to eq(branch["suggested_options"])
    expect(payload).not_to have_key("paused_flows")
  end

  it "suspends a booking without losing the confirmation candidate, and says it can be picked up" do
    selected_option = { "selection_id" => "sel_1", "room_type_name" => "Deluxe Room" }
    branch = {
      "branch_id" => "branch-1",
      "target_month" => 8,
      "suggested_options" => [ { "room_type_name" => "Deluxe Room", "options" => [] } ],
      "confirmation_candidate" => selected_option,
      "selected_option" => selected_option
    }
    payload = described_class.new(slots_payload: {}).activate_booking(branch, pending_question: "confirm_selection")

    suspended = described_class.new(slots_payload: payload).suspend_booking_for_information(
      intent: "hotel_policy",
      topic: "hotel_policy",
      pending_question: "confirm_selection"
    )
    manager = described_class.new(slots_payload: suspended)

    expect(suspended["booking_task"]["status"]).to eq("suspended")
    expect(manager).to be_suspended_booking_resumable
    expect(manager.booking_pending_question).to eq("confirm_selection")
    expect(manager.booking_branch["confirmation_candidate"]).to eq(selected_option)
  end

  it "does not pick up an expired suspended booking" do
    payload = described_class.new(slots_payload: {}).activate_booking({ "target_month" => 8 }, pending_question: "select_option")
    suspended = described_class.new(slots_payload: payload, now: 2.hours.ago).suspend_booking_for_information(
      intent: "hotel_information",
      topic: "hotel_faq",
      pending_question: "select_option"
    )

    expect(described_class.new(slots_payload: suspended, now: Time.current)).not_to be_suspended_booking_resumable
  end

  # Expiry used to be a fact about the greeting and not about the dates: the
  # booking could not be resumed, but its branch was still what the next turn
  # merged the guest's words into, so an enquiry abandoned last month came back
  # and quietly searched the month it had named.
  it "takes the dates with it when a suspended booking expires" do
    payload = described_class.new(slots_payload: {}).activate_booking(
      { "target_month" => 8, "target_year" => 2026 }, pending_question: "select_option"
    )
    suspended = described_class.new(slots_payload: payload, now: 2.hours.ago).suspend_booking_for_information(
      intent: "hotel_information",
      topic: "hotel_faq",
      pending_question: "select_option"
    )

    manager = described_class.new(slots_payload: suspended, now: Time.current)

    expect(manager.booking_pending_question).to be_nil
    expect(manager.booking_branch["target_month"]).to be_nil
    expect(manager.booking_task["status"]).to eq("expired")
  end
end
