require "rails_helper"

RSpec.describe AiConcierge::Agents::MessengerAgent do
  let(:hotel) { create(:hotel, :with_ai_concierge) }

  it "renders the hotel-specific greeting" do
    result = described_class.new(hotel: hotel, context: { reply_type: :greeting }).call

    expect(result["reply_message"]).to eq("Hello, welcome to #{hotel.name}! I can help with bookings, stay details, and more about the hotel. What would you like to inquire about?")
  end

  it "renders grouped booking suggestions by room type" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :suggest_options,
      month_label: "early August 2026",
      guest_label: "2 adults",
      options: [
        {
          "room_type_name" => "Garden Prestige Suite",
          "options" => [
            { "position" => 1, "check_in" => "2026-08-03", "check_out" => "2026-08-05", "nights" => 2, "currency" => "MYR", "total_price" => 520.0 },
            { "position" => 2, "check_in" => "2026-08-04", "check_out" => "2026-08-06", "nights" => 2, "currency" => "USD", "total_price" => 120.0 }
          ]
        }
      ]
    }).call

    expect(result["reply_message"]).to include("*Garden Prestige Suite*")
    expect(result["reply_message"]).to include("  Option 1: 3 August 2026 - 5 August 2026 (2 nights)")
    expect(result["reply_message"]).to include("  Option 2: 4 August 2026 - 6 August 2026 (2 nights)")
    expect(result["reply_message"]).to include('Reply with the room type name and option number or date you want, for example: "Ocean Villa King option 1" or "Executive Penthouse on May 21"')
    expect(result["reply_message"]).to include("You may visit this link for more details:")
  end

  it "renders the narrowed room type options when asking for an option number" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :room_type_requires_option_number,
      room_type_name: "Executive Penthouse",
      room_options: {
        "room_type_name" => "Executive Penthouse",
        "options" => [
          { "position" => 1, "check_in" => "2026-08-03", "check_out" => "2026-08-05", "nights" => 2, "currency" => "MYR", "total_price" => 520.0 },
          { "position" => 2, "check_in" => "2026-08-04", "check_out" => "2026-08-06", "nights" => 2, "currency" => "MYR", "total_price" => 540.0 }
        ]
      }
    }).call

    expect(result["reply_message"]).to include("I found multiple options under Executive Penthouse:")
    expect(result["reply_message"]).to include("*Executive Penthouse*")
    expect(result["reply_message"]).to include("  Option 1: 3 August 2026 - 5 August 2026 (2 nights)")
    expect(result["reply_message"]).to include("  Option 2: 4 August 2026 - 6 August 2026 (2 nights)")
  end

  it "renders confirmation with yes and no prompt" do
    room_type = create(:room_type, hotel: hotel, name: "Executive Penthouse", description: "A luxury penthouse with city views.", amenities: [ "wifi", "ac" ])
    result = described_class.new(hotel: hotel, context: {
      reply_type: :ask_confirmation,
      selected_option: {
        "room_type_id" => room_type.id,
        "room_type_name" => "Executive Penthouse",
        "check_in" => "2026-08-03",
        "check_out" => "2026-08-05",
        "currency" => "MYR",
        "total_price" => 520.0
      }
    }).call

    expect(result["reply_message"]).to include("Would you like to confirm your quotation for this room start from 3 August 2026 until 5 August 2026 for RM 520.00.")
    expect(result["reply_message"]).to include("*Executive Penthouse*")
    expect(result["reply_message"]).to include("A luxury penthouse with city views.")
    expect(result["reply_message"]).to include("Room Amenities:")
    expect(result["reply_message"]).to include("- Free WiFi")
    expect(result["reply_message"]).to include("- Air Conditioning")
    expect(result["reply_message"]).to include("Please reply *Yes* to confirm the book and *No* to reconsider the choices.")
  end

  it "renders hotel policy as a multiline block" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :hotel_policy,
      result: {
        "check_in_time" => "15:00",
        "check_out_time" => "12:00",
        "cancellation_policy" => "24 hours"
      }
    }).call

    expect(result["reply_message"]).to eq([
      "Welcome to #{hotel.name}! Here is our hotel policy:",
      "- Check-in starts at: *15:00*",
      "- Check-out is at: *12:00*",
      "- Cancellation: *24 hours*"
    ].join("\n"))
  end

  it "renders a structured booking context list" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :booking_context,
      bookings: [
        { "date_range" => "May 21 - May 23", "room_type_name" => "Executive Penthouse" }
      ]
    }).call

    expect(result["reply_message"]).to include("According to our system, we found your active booking:")
    expect(result["reply_message"]).to include("- *May 21 - May 23*: Executive Penthouse")
  end

  it "renders the end confirmation prompt for a booking flow" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :confirm_to_end_conversation,
      end_confirmation_mode: :cancel_booking_attempt
    }).call

    expect(result["reply_message"]).to eq("Do you want to start over with a new booking, ask about hotel policies or information, or end the conversation?")
  end

  it "renders the cancelled booking attempt next-step prompt" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :booking_attempt_cancelled_next_step
    }).call

    expect(result["reply_message"]).to eq("I've cancelled your booking attempt. Would you like to start a new booking, ask about hotel policies or information, or end the conversation?")
  end

  it "renders the generic end confirmation prompt" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :confirm_to_end_conversation,
      end_confirmation_mode: :generic
    }).call

    expect(result["reply_message"]).to eq("Dear guest, do you have anything else to ask?")
  end

  it "renders the smart party split message when adults are partially known" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :ask_party_split,
      party_size_total: 4,
      adults: 2
    }).call

    expect(result["reply_message"]).to include("I've noted 2 adults. For the remaining 2 people, are they children?")
    expect(result["reply_message"]).to include("Please reply *Yes* to confirm")
  end

  it "renders the booking link ready message" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :booking_link_ready,
      result: {
        "booking_url" => "http://test.com",
        "currency" => "MYR",
        "total_amount" => 7040.0,
        "expires_at" => "2026-05-06T08:04:00Z",
        "selected_option" => {
          "check_in" => "2026-07-03",
          "check_out" => "2026-07-07"
        }
      }
    }).call

    expect(result["reply_message"]).to include("Great, I've prepared your booking quote:")
    expect(result["reply_message"]).to include("- Date: *3 July 2026 - 7 July 2026*")
    expect(result["reply_message"]).to include("- Total: *RM 7040.00*")
    expect(result["reply_message"]).to include("Please note that the quotation link will expire at 8:04 AM.")
    expect(result["reply_message"]).to include("http://test.com")
  end

  it "renders the guest count message with a specific date" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :ask_guest_count,
      check_in: "2026-05-24"
    }).call

    expect(result["reply_message"]).to eq("How many guests should I check for on May 24?")
  end

  it "renders the guest count message with a month label fallback" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :ask_guest_count,
      month_label: "May 2026"
    }).call

    expect(result["reply_message"]).to eq("How many guests should I check for in May 2026?")
  end

  it "renders the specific timing clarification message" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :ask_specific_timing,
      month_label: "May 2026"
    }).call

    expect(result["reply_message"]).to eq("You want to make a booking in May 2026. May I know the exact check-in date or assumption range, e.g: *early*, *mid*, and *late*?")
  end

  it "renders an empty booking context state" do
    result = described_class.new(hotel: hotel, context: {
      reply_type: :booking_context,
      bookings: []
    }).call

    expect(result["reply_message"]).to eq("According to our system, we could not find an active booking at the moment.")
  end

  it "prompts before ending the conversation when options were shown" do
    prospect = create(:prospect, hotel: hotel)
    conversation_state = create(:prospect_conversation_state, prospect: prospect, pending_question: "select_option")
    conversation_state.update!(
      active_topic: "booking_search",
      active_flow: "booking_search",
      slots_payload: {
        "booking_task" => {
          "status" => "collecting_slots",
          "pending_question" => "select_option",
          "branch" => {
            "topic" => "booking_search",
            "suggested_options" => [
              { "room_type_name" => "Executive Penthouse", "options" => [ { "position" => 1, "selection_id" => "1" } ] }
            ]
          }
        }
      }
    )

    # No model fake for the loop: "nevermind" is caught by the control handler
    # before it ever runs, which is the point of settling control
    # deterministically. The stylist still runs afterwards -- it reads the
    # finished sentence, and a control reply is a sentence like any other.
    stub_concierge_stylist

    result = AiConcierge::Orchestration::TurnOrchestrator.new(hotel: hotel, message: "nevermind", prospect_public_id: prospect.public_id).call

    expect(result.payload[:reply_message]).to eq("Do you want to start over with a new booking, ask about hotel policies or information, or end the conversation?")
    state = prospect.prospect_conversation_state.reload
    expect(state.pending_question).to eq("confirm_to_end_conversation")
    expect(state.flow_status).to eq("active")
  end

  it "extracts pure digit as party_size_total when pending_question is guest_count" do
    prospect = create(:prospect, hotel: hotel)
    conversation_state = create(:prospect_conversation_state, prospect: prospect, pending_question: "guest_count")
    conversation_state.update!(slots_payload: {
      "active" => { "target_month" => 6, "target_year" => 2026, "month_segment" => "early" }
    })

    # The model passes no slots; InputNormalizer is what finds the 4.
    stub_concierge_model(scripted: {
      "4" => { tool: "advance_booking", arguments: { "slots" => {}, "signals" => {} } }
    })

    AiConcierge::Orchestration::TurnOrchestrator.new(hotel: hotel, message: "4", prospect_public_id: prospect.public_id).call

    payload = prospect.prospect_conversation_state.reload.slots_payload
    expect(payload.dig("booking_task", "branch", "party_size_total")).to eq(4)
    expect(payload).not_to have_key("active")
  end

  it "strips hallucinated month_segment for vague month requests" do
    prospect = create(:prospect, hotel: hotel)
    conversation_state = create(:prospect_conversation_state, prospect: prospect)

    # The model hallucinates month_segment="early" for a bare "june".
    stub_concierge_model(scripted: {
      "can i book on june" => { tool: "advance_booking", arguments: { "slots" => { "target_month" => 6, "target_year" => 2026, "month_segment" => "early" }, "signals" => {} } }
    })

    result = AiConcierge::Orchestration::TurnOrchestrator.new(hotel: hotel, message: "can i book on june", prospect_public_id: prospect.public_id).call

    # Should trigger ask_specific_timing because month_segment was stripped
    expect(result.payload[:reply_message]).to include("May I know the exact check-in date or assumption range")
    payload = prospect.prospect_conversation_state.reload.slots_payload
    expect(payload.dig("booking_task", "branch", "month_segment")).to be_nil
    expect(payload).not_to have_key("active")
  end

  it "extracts pure month segment when pending_question is specific_timing" do
    prospect = create(:prospect, hotel: hotel)
    conversation_state = create(:prospect_conversation_state, prospect: prospect, pending_question: "specific_timing")
    conversation_state.update!(slots_payload: {
      "active" => { "target_month" => 6, "target_year" => 2026 }
    })

    # The model gets this one right.
    stub_concierge_model(scripted: {
      "mid" => { tool: "advance_booking", arguments: { "slots" => { "month_segment" => "mid" }, "signals" => {} } }
    })

    result = AiConcierge::Orchestration::TurnOrchestrator.new(hotel: hotel, message: "mid", prospect_public_id: prospect.public_id).call

    # Should now ask for duration because month_segment is extracted
    expect(result.payload[:reply_message]).to include("How many days and nights will you be staying?")
    payload = prospect.prospect_conversation_state.reload.slots_payload
    expect(payload.dig("booking_task", "branch", "month_segment")).to eq("mid")
    expect(payload).not_to have_key("active")
  end

  it "treats a date with ok as a specific timing answer, not confirmation" do
    prospect = create(:prospect, hotel: hotel)
    conversation_state = create(:prospect_conversation_state, prospect: prospect, pending_question: "specific_timing")
    conversation_state.update!(slots_payload: {
      "active" => { "target_month" => 6, "target_year" => 2026 }
    })

    # The model reads the trailing "ok?" as a yes. pending_question is what
    # decides a "yes" is not on offer here, so the date wins.
    stub_concierge_model(scripted: {
      "23 june ok?" => { tool: "advance_booking", arguments: { "slots" => { "confirmation" => "yes" }, "signals" => {} } }
    })

    result = AiConcierge::Orchestration::TurnOrchestrator.new(hotel: hotel, message: "23 june ok?", prospect_public_id: prospect.public_id).call

    expect(result.payload[:reply_message]).to eq("How many days and nights will you be staying?")
    expect(result.payload[:action_name]).to eq("request_quote")
    payload = prospect.prospect_conversation_state.reload.slots_payload
    expect(payload.dig("booking_task", "branch", "check_in")).to eq("2026-06-23")
  end

  it "does not attach request quote action to clarification replies" do
    prospect = create(:prospect, hotel: hotel)

    # A booking attempt that states nothing yet.
    stub_concierge_model(scripted: {
      "can i make booking?" => { tool: "advance_booking", arguments: { "slots" => {}, "signals" => {} } }
    })

    result = AiConcierge::Orchestration::TurnOrchestrator.new(hotel: hotel, message: "can i make booking?", prospect_public_id: prospect.public_id).call

    expect(result.payload[:reply_message]).to eq("Sure, which date or month do you plan to arrive for check-in?")
    expect(result.payload[:action_name]).to eq("request_quote")
  end
end
