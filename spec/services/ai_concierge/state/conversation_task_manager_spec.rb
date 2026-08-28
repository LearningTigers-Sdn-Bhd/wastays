require "rails_helper"

RSpec.describe AiConcierge::State::ConversationTaskManager do
  describe "existing booking task" do
    it "scopes secure lookup state to one conversation" do
      payload = described_class.new(slots_payload: {}).request_existing_booking_code(conversation_id: 12)
      manager = described_class.new(slots_payload: payload)

      expect(manager.existing_booking_pending?(conversation_id: 12)).to be(true)
      expect(manager.existing_booking_pending?(conversation_id: 13)).to be(false)
    end

    it "requests a confirmation code without changing the new-booking task" do
      manager = described_class.new(slots_payload: {})
      original_booking = manager.booking_task

      payload = manager.request_existing_booking_code

      expect(payload["existing_booking_task"]).to include(
        "status" => "awaiting_confirmation_code",
        "pending_question" => "confirmation_code"
      )
      expect(payload["booking_task"]).to eq(original_booking)
    end

    it "offers the portal without changing the new-booking task" do
      manager = described_class.new(slots_payload: {})
      original_booking = manager.booking_task

      payload = manager.offer_existing_booking_portal(request_kind: :portal_general)

      expect(payload.dig("existing_booking_task", "status")).to eq("portal_offered")
      expect(payload.dig("ui_task", "suggestion_group")).to eq("portal_offer")
      expect(payload["booking_task"]).to eq(original_booking)
    end

    it "locks the lookup after five rejected codes" do
      payload = described_class.new(slots_payload: {}).request_existing_booking_code
      5.times { payload = described_class.new(slots_payload: payload).reject_existing_booking_code }

      expect(payload.dig("existing_booking_task", "status")).to eq("locked")
      expect(payload.dig("ui_task", "suggestion_group")).to eq("magic_link_failure")
    end

    it "stores only allowlisted suggestion groups" do
      manager = described_class.new(slots_payload: {})

      expect(manager.show_suggestions("greeting").dig("ui_task", "suggestion_group")).to eq("greeting")
      expect(manager.show_suggestions("https://example.com").dig("ui_task", "suggestion_group")).to be_nil
    end
  end

  describe "booking purpose" do
    it "normalizes existing tasks to booking without changing the state version" do
      manager = described_class.new(slots_payload: {})

      expect(manager.booking_purpose).to eq("booking")
      expect(manager).not_to be_price_exploration
      expect(manager.payload["state_version"]).to eq(3)
    end

    it "keeps price exploration through booking updates and clears it on reset" do
      priced = described_class.new(slots_payload: {}).set_booking_purpose("price_exploration")
      active = described_class.new(slots_payload: priced).activate_booking(
        { "target_month" => 8 }, pending_question: "price_option_exploration"
      )

      expect(active.dig("booking_task", "purpose")).to eq("price_exploration")
      expect(active.dig("booking_task", "status")).to eq("exploring_prices")
      expect(described_class.new(slots_payload: active).reset_booking_task.dig("booking_task", "purpose")).to eq("booking")
    end

    it "keeps price exploration while an information answer suspends the booking" do
      priced = described_class.new(slots_payload: {}).set_booking_purpose("price_exploration")
      active = described_class.new(slots_payload: priced).activate_booking(
        { "target_month" => 8 }, pending_question: "price_option_exploration"
      )
      suspended = described_class.new(slots_payload: active).suspend_booking_for_information(
        intent: "hotel_policy",
        topic: "hotel_policy",
        pending_question: "price_option_exploration"
      )

      expect(suspended.dig("booking_task", "purpose")).to eq("price_exploration")
      expect(suspended.dig("booking_task", "status")).to eq("suspended")
    end
  end

  describe "sales offers" do
    it "adds the sales task without changing the state version" do
      manager = described_class.new(slots_payload: {})

      expect(manager.payload["state_version"]).to eq(3)
      expect(manager.sales_task).to eq(
        "last_optional_action" => nil,
        "suppress_next_optional_offer" => false,
        "refusal_acknowledgment_pending" => false
      )
    end

    it "records and declines an optional offer without changing booking or information state" do
      initial = described_class.new(slots_payload: {}).update_information_task(intent: "hotel_policy", topic: "hotel_policy")
      normalized = described_class.new(slots_payload: initial).payload
      offered = described_class.new(slots_payload: normalized).record_optional_sales_offer("offer_booking_help")
      declined = described_class.new(slots_payload: offered).decline_optional_sales_offer

      expect(declined["booking_task"]).to eq(normalized["booking_task"])
      expect(declined["information_task"]).to eq(normalized["information_task"])
      expect(declined.dig("sales_task", "last_optional_action")).to be_nil
      expect(declined.dig("sales_task", "suppress_next_optional_offer")).to be(true)
      expect(declined.dig("sales_task", "refusal_acknowledgment_pending")).to be(true)
    end

    it "clears the acknowledgment without consuming suppression" do
      offered = described_class.new(slots_payload: {}).record_optional_sales_offer("offer_price_search")
      declined = described_class.new(slots_payload: offered).decline_optional_sales_offer
      cleared = described_class.new(slots_payload: declined).clear_optional_sales_offer

      expect(cleared.dig("sales_task", "suppress_next_optional_offer")).to be(true)
      expect(cleared.dig("sales_task", "refusal_acknowledgment_pending")).to be(false)
    end

    it "consumes one suppressed optional offer" do
      offered = described_class.new(slots_payload: {}).record_optional_sales_offer("offer_booking_help")
      declined = described_class.new(slots_payload: offered).decline_optional_sales_offer
      consumed = described_class.new(slots_payload: declined).consume_sales_offer_suppression

      expect(consumed.dig("sales_task", "suppress_next_optional_offer")).to be(false)
      expect(consumed.dig("sales_task", "refusal_acknowledgment_pending")).to be(false)
    end
  end

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

  it "normalizes legacy active state into the current booking task" do
    branch = { "branch_id" => "branch-1", "target_month" => 8 }

    payload = described_class.new(slots_payload: { "active" => branch, "paused_flows" => [] }).payload

    expect(payload["state_version"]).to eq(3)
    expect(payload["booking_task"]["branch"]["target_month"]).to eq(8)
    expect(payload).not_to have_key("active")
    expect(payload).not_to have_key("paused_flows")
  end

  it "normalizes legacy paused booking flow into a suspended current booking task" do
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
