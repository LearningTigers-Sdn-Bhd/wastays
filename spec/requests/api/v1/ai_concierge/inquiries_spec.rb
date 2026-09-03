require "rails_helper"
require "ostruct"

RSpec.describe "API V1 AI Concierge Inquiries", type: :request, frozen_time: Time.zone.local(2026, 7, 15, 12) do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:api_key) { create(:api_key, bearer: hotel) }
  let(:headers) { { "Authorization" => "Bearer #{api_key.token}", "Content-Type" => "application/json" } }
  let(:path) { "/api/v1/hotels/#{hotel.id}/ai_concierge/inquiries" }
  let(:slug_path) { "/api/v1/hotels/#{hotel.slug}/ai_concierge/inquiries" }
  let(:phone) { "0123456789" }

  before do
    create(:property_policy, hotel: hotel, check_in_time: "15:00", check_out_time: "12:00", cancellation_policy: "24 hours")
    create(:guest, phone: "+60123456789")
    allow_any_instance_of(HotelKnowledges::SearchService).to receive(:call).and_return([])
    stub_interpreter
  end

  describe "POST /api/v1/hotels/:hotel_id/ai_concierge/inquiries" do
    it "returns 401 without authorization" do
      post path, params: { message: "Hello", phone: phone }.to_json, headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
      expect(parsed_body["error"]).to include("Unauthorized")
    end

    it "returns 403 for a hotel not owned by the API key" do
      other_hotel = create(:hotel)
      other_path = "/api/v1/hotels/#{other_hotel.id}/ai_concierge/inquiries"

      post other_path, params: { message: "Hello", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(parsed_body["error"]).to include("Forbidden")
    end

    it "returns 422 when message is blank" do
      post path, params: { message: "", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(parsed_body["error"]).to eq("Message is required")
    end

    it "accepts nested inquiry payloads" do
      post path, params: { inquiry: { message: "Hello", phone: phone } }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to be_present
      expect(parsed_body["prospect_public_id"]).to be_present
    end

    it "returns 422 when message exceeds max length" do
      long_message = "x" * 2001

      post path, params: { message: long_message, phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(parsed_body["error"]).to eq("Message is too long (max 2000 characters)")
    end

    # The thread's mode decides who may answer. Nothing on this path used to
    # read it, so a staff member holding a WhatsApp thread from the inbox still
    # had the assistant replying over the top of them.
    context "when a staff member is holding the thread" do
      let(:conversation) { Conversation.order(:id).last }

      before do
        post path, params: { message: "Hello", phone: phone }.to_json, headers: headers
        Concierge::TakeOverConversation.new(conversation: conversation, user: create(:user)).call
      end

      it "answers with nothing to send" do
        post path, params: { message: "Are you there?", phone: phone }.to_json, headers: headers

        expect(response).to have_http_status(:ok)
        expect(parsed_body["reply_message"]).to be_nil
        expect(parsed_body["needs_human_support"]).to be(true)
        expect(parsed_body["prospect_public_id"]).to be_present
      end

      # Silence is only the answer. The message itself still has to reach the
      # person who is expected to reply to it.
      it "still files the guest's message on the thread" do
        expect {
          post path, params: { message: "Are you there?", phone: phone }.to_json, headers: headers
        }.to change { conversation.messages.from_guest.count }.by(1)

        expect(conversation.messages.chronological.last.body).to eq("Are you there?")
      end

      it "writes no reply of its own" do
        expect {
          post path, params: { message: "Are you there?", phone: phone }.to_json, headers: headers
        }.not_to change { conversation.messages.where(sender_role: "bot").count }
      end

      it "answers again once the thread goes back to the bot" do
        conversation.return_to_bot!

        post path, params: { message: "What is the policy of this hotel?", phone: phone }.to_json, headers: headers

        expect(parsed_body["reply_message"]).to be_present
      end
    end

    it "answers hotel policy questions" do
      doc = create(:hotel_knowledge_document, hotel: hotel, category: "policy", title: "Quiet Hours", embedding_status: "indexed")
      create(:hotel_knowledge_chunk, document: doc, chunk_index: 0, content: "Quiet hours start at 10 PM.")

      post path, params: { message: "What is the policy of this hotel?", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include(
        "- You can check in from 15:00.",
        "- Check-out is by 12:00.",
        "- You can cancel under these terms: 24 hours.",
        "- Quiet Hours Quiet hours start at 10 PM.",
        "If that suits your plans, I can help you compare rooms for your dates. Is there anything else you’d like to know?"
      )
      expect(parsed_body["reply_message"]).not_to match(/not provided|thank you for your inquiry|please let us know/i)
      expect(parsed_body["needs_human_support"]).to be(false)
      expect(parsed_body["action_name"]).to be_nil
      expect(parsed_body["prospect_public_id"]).to be_present
    end

    it "keeps the chat open after a sales refusal and suppresses the rest of the information run" do
      post path, params: { message: "What time is check-out?", phone: phone }.to_json, headers: headers
      expect(parsed_body["reply_message"]).to include("If that suits your plans")

      post path, params: { message: "no thanks", phone: phone }.to_json, headers: headers
      expect(parsed_body["reply_message"]).to eq("No problem. How else can I help you?")

      post path, params: { message: "What time is check-in?", phone: phone }.to_json, headers: headers
      expect(parsed_body["reply_message"]).to include("You can check in from 15:00.")
      expect(parsed_body["reply_message"]).not_to include("compare rooms")

      post path, params: { message: "What time is check-out?", phone: phone }.to_json, headers: headers
      expect(parsed_body["reply_message"]).not_to include("compare rooms")
      expect(parsed_body.keys).to contain_exactly("reply_message", "needs_human_support", "action_name", "prospect_public_id")
    end

    it "records a knowledge diagnostic for unanswered knowledge turns without changing the public payload" do
      expect {
        post path, params: { message: "Do you have an faq?", phone: phone }.to_json, headers: headers
      }.to change(HotelKnowledgeDiagnostic, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(parsed_body.keys).to contain_exactly("reply_message", "needs_human_support", "action_name", "prospect_public_id")

      diagnostic = HotelKnowledgeDiagnostic.last
      expect(diagnostic.hotel).to eq(hotel)
      expect(diagnostic.prospect).to eq(Prospect.lookup_by_phone(phone).first)
      expect(diagnostic.intent).to eq("hotel_information")
      expect(diagnostic.topic).to eq("hotel_faq")
      expect(diagnostic.question).to eq("Do you have an faq?")
      expect(diagnostic.answer_mode).to eq("unavailable")
      expect(diagnostic.suggested_category).to eq("faq")
    end

    it "does not record noisy diagnostics for strong retrieved knowledge answers" do
      allow_any_instance_of(HotelKnowledges::SearchService).to receive(:call).and_return([
        {
          "content" => "Breakfast is served daily from 7 AM to 10 AM.",
          "document_title" => "Breakfast",
          "category" => "faq",
          "distance" => 0.12
        }
      ])

      expect {
        post path, params: { message: "Do you have an faq?", phone: phone }.to_json, headers: headers
      }.not_to change(HotelKnowledgeDiagnostic, :count)

      expect(response).to have_http_status(:ok)
      expect(parsed_body.keys).to contain_exactly("reply_message", "needs_human_support", "action_name", "prospect_public_id")
      expect(parsed_body["reply_message"])
        .to eq(
          "Breakfast is served daily from 7 AM to 10 AM.\n\n" \
          "If that suits your plans, I can help you compare rooms for your dates. Is there anything else you’d like to know?"
        )
    end

    it "accepts hotel slugs in the path" do
      post slug_path, params: { message: "What is the policy of this hotel?", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("- You can check in from 15:00.")
      expect(parsed_body["reply_message"]).not_to include(hotel.name)
    end

    it "answers general hotel information questions" do
      post path, params: { message: "Tell me about the hotel", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include(hotel.name, hotel.city)
      expect(parsed_body["reply_message"]).not_to include(hotel.address)
      expect(parsed_body["reply_message"]).to end_with("What matters most for your stay: facilities, location, or room choices?")
    end

    it "answers hotel faq questions" do
      doc = create(:hotel_knowledge_document, hotel: hotel, category: "faq", title: "General", embedding_status: "indexed")
      create(:hotel_knowledge_chunk, document: doc, chunk_index: 0, content: "Q: What time is breakfast?\nA: Breakfast is served daily from 7 AM to 10 AM.")

      post path, params: { message: "Do you have an faq?", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"])
        .to eq(
          "General Q: What time is breakfast? A: Breakfast is served daily from 7 AM to 10 AM.\n\n" \
          "If that suits your plans, I can help you compare rooms for your dates. Is there anything else you’d like to know?"
        )
    end

    it "returns the full nearby attractions list" do
      create(:nearby_attraction, hotel: hotel, name: "Sky Bridge", description: "Scenic landmark", address: "Cable Car Station")
      create(:nearby_attraction, hotel: hotel, name: "Night Market", description: "Local food and shopping", address: "Town Square")

      post path, params: { message: "What attractions are nearby?", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Here are the available details")
      expect(parsed_body["reply_message"]).to include("Sky Bridge")
      expect(parsed_body["reply_message"]).to include("Night Market")
    end

    it "answers room information questions with fuzzy matching" do
      create(:room_type,
        hotel: hotel,
        name: "Executive Suite",
        description: "Large suite with sea view.",
        max_adults: 3,
        max_children: 2,
        amenities: %w[wifi balcony tv]
      )

      post path, params: { message: "Tell me about the exec suite", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Executive Suite: Large suite with sea view")
      expect(parsed_body["reply_message"]).to include("amenities include Free WiFi")
      expect(parsed_body["reply_message"]).to include("Large suite with sea view.")
      expect(parsed_body["reply_message"]).to include("amenities include Free WiFi, Balcony / Terrace, Flat-screen TV")
    end

    it "asks the guest to clarify when a room question matches multiple room types" do
      create(:room_type, hotel: hotel, name: "Ocean Villa King")
      create(:room_type, hotel: hotel, name: "Ocean Villa Twin")

      post path, params: { message: "Tell me about the ocean villa", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("several matching room types")
      expect(parsed_body["reply_message"]).to include("Ocean Villa King")
      expect(parsed_body["reply_message"]).to include("Ocean Villa Twin")
    end

    it "preserves the selected month when the guest only answers duration" do
      post path, params: { message: "hello, any booking for early august?", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 days 2 nights", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("early August")
      expect(parsed_body["reply_message"]).to include("How many guests")
      expect(parsed_body["reply_message"]).not_to include("May")
    end

    it "asks when if the user only shares guest count" do
      post path, params: { message: "hello, is there any booking for 2 adults", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("date or month")
      expect(parsed_body["reply_message"]).not_to include("May")
      expect(parsed_body["reply_message"]).not_to include("August")
    end

    it "asks for duration after the guest later provides a month window" do
      post path, params: { message: "hello, is there any booking for 2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "early august", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("How many days and nights")
    end

    it "preserves people as an unresolved split after the guest later provides duration" do
      post path, params: { message: "can i book for early june? for 2 people", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 days 1 night", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("For 2 people")
      expect(parsed_body["reply_message"]).to include("adults and how many are children")
    end

    it "renders one numbered row per option" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 1, 2, 3, 4 ])

      post path, params: { message: "hello, any booking for early august?", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 days 2 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("*1. Garden Prestige Suite* · August 1 to August 3 — from RM")
      expect(parsed_body["reply_message"]).to include("*2. Garden Prestige Suite* · August 2 to August 4 — from RM")
      expect(parsed_body["reply_message"]).to include('Reply with the number of the option you want, e.g. "1".')
    end

    it "explores a price before requiring booking and quotation confirmations" do
      room_type = seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 28, 29, 30, 31 ])
      room_type.update!(description: "A quiet suite facing the garden.", amenities: %w[wifi balcony])
      stub_concierge_model(
        room_type_names: [ "Garden Prestige Suite" ],
        scripted: {
          "what is the cheapest room price?" => { tool: "advance_booking", arguments: { slots: {} } },
          "28 august to 31 august" => {
            tool: "advance_booking",
            arguments: {
              slots: { check_in: "2026-08-28", check_out: "2026-08-31", nights: 3, days: 4 },
              evidence: { timing: "28 august", checkout: "31 august", duration: "28 august to 31 august" }
            }
          },
          "2 adults" => {
            tool: "advance_booking",
            arguments: { slots: { adults: 2, children: 0 }, evidence: { party: "2 adults" } }
          },
          "1" => { tool: "advance_booking", arguments: { slots: { option_number: 1 } } },
          "book this option" => { tool: "advance_booking", arguments: { slots: {} } },
          "yes" => { tool: "advance_booking", arguments: { slots: { confirmation: "yes" } } }
        }
      )

      post path, params: { message: "what is the cheapest room price?", phone: phone }.to_json, headers: headers
      expect(parsed_body["action_name"]).to be_nil

      post path, params: { message: "28 august to 31 august", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers

      expect(parsed_body["reply_message"]).to include("Lowest starting option: *1. Garden Prestige Suite*")
      expect(parsed_body["reply_message"]).to include("28 August 2026 - 31 August 2026 · 3 nights · 2 adults · 1 room")
      expect(parsed_body["action_name"]).to be_nil

      post path, params: { message: "1", phone: phone }.to_json, headers: headers

      expect(parsed_body["reply_message"]).to include("A quiet suite facing the garden.")
      expect(parsed_body["reply_message"]).to include("Available rates:")
      expect(parsed_body["reply_message"]).to include("say *book this option* when you are ready")
      expect(parsed_body["reply_message"]).not_to include("Quotation link:")
      expect(parsed_body["action_name"]).to be_nil

      post path, params: { message: "yes", phone: phone }.to_json, headers: headers

      expect(parsed_body["reply_message"]).to include("still only being compared")
      expect(parsed_body["action_name"]).to be_nil

      post path, params: { message: "book this option", phone: phone }.to_json, headers: headers

      expect(parsed_body["reply_message"]).to include("Please reply *Yes* to confirm the book")
      expect(parsed_body["reply_message"]).not_to include("Quotation link:")
      expect(parsed_body["action_name"]).to eq("request_quote")

      post path, params: { message: "yes", phone: phone }.to_json, headers: headers

      expect(parsed_body["reply_message"]).to include("Quotation link:")
    end

    # The thread from a live chat: two room types on the same fixed dates, both
    # of them "Option 1" under the old per-room-type numbering, so the guest
    # was asked twice for something they had already said.
    it "resolves a number and a room name on fixed dates, without asking again" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 28, 29, 30, 31 ], max_adults: 3)
      seed_room_type_options("Executive Penthouse", month: 8, days: [ 28, 29, 30, 31 ], max_adults: 3, base_price: 900)

      post path, params: { message: "book 28 august to 31 august", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 adults", phone: phone }.to_json, headers: headers

      expect(parsed_body["reply_message"]).to include("*1. Garden Prestige Suite*")
      expect(parsed_body["reply_message"]).to include("*2. Executive Penthouse*")

      post path, params: { message: "2", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Executive Penthouse")
      expect(parsed_body["reply_message"]).not_to include("I couldn't match that option")
      expect(parsed_body["reply_message"]).not_to include("I found option")
    end

    # The model reading "option 1" as one adult is a reading it really returned:
    # the 1 came back quoted as the words that say the party size. A booking for
    # three then became a booking for one, which threw the catalogue away and
    # asked the guest how many of the remaining two were children.
    it "does not read the option number as a party size" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 28, 29, 30, 31 ], max_adults: 3)
      seed_room_type_options("Executive Penthouse", month: 8, days: [ 28, 29, 30, 31 ], max_adults: 3, base_price: 900)
      stub_concierge_model(
        room_type_names: ROOM_VOCABULARY,
        scripted: {
          "option 1" => {
            tool: "advance_booking",
            arguments: {
              "slots" => { "adults" => 1 },
              "evidence" => { "party" => "1" }
            }
          }
        }
      )

      post path, params: { message: "book 28 august to 31 august", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "option 1", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Garden Prestige Suite")
      expect(parsed_body["reply_message"]).not_to include("are they children")
      expect(parsed_body["reply_message"]).not_to include("I've noted 1 adults")
    end

    # Both of these answered a question the hotel had just asked, and both used
    # to be met with the same question again: the ladder asks for days and
    # nights, and the party split tells the guest in as many words to reply Yes.
    it "takes a bare number as the answer to the duration question" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 11, 12, 13, 14 ])

      post path, params: { message: "mid august", phone: phone }.to_json, headers: headers
      post path, params: { message: "2", phone: phone }.to_json, headers: headers

      expect(parsed_body["reply_message"]).to include("How many guests")
      expect(parsed_body["reply_message"]).not_to include("How many days and nights")
    end

    it "takes yes as the answer to the party split, even when the model sends nothing" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 11, 12, 13, 14 ], max_adults: 4)
      stub_concierge_model(
        room_type_names: ROOM_VOCABULARY,
        scripted: { "yes" => { tool: "advance_booking", arguments: { "slots" => {} } } }
      )

      post path, params: { message: "mid august", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 days 2 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "4 people", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      expect(parsed_body["reply_message"]).to include("are they children")

      post path, params: { message: "yes", phone: phone }.to_json, headers: headers

      expect(parsed_body["reply_message"]).not_to include("are they children")
      expect(parsed_body["reply_message"]).to include("2 adults and 2 children")
    end

    it "selects a shown option by its number" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 1, 2, 3, 4 ])

      post path, params: { message: "hello, any booking for early august?", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 days 2 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "option 2", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Garden Prestige Suite")
      expect(parsed_body["reply_message"]).to include("Please reply *Yes* to confirm the book and *No* to reconsider the choices.")
    end

    it "resumes the saved option set after a hotel policy interruption" do
      seed_room_type_options("Ocean Villa King", month: 5, days: [ 21, 22, 23, 24, 25, 26 ])
      seed_room_type_options("Executive Penthouse", month: 5, days: [ 21, 22, 23, 24, 25, 26 ])
      seed_room_type_options("Garden Prestige Suite", month: 5, days: [ 21, 22, 23, 24, 25, 26 ])

      post path, params: { message: "late may", phone: phone }.to_json, headers: headers
      post path, params: { message: "4 days 3 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "any hotel policies?", phone: phone }.to_json, headers: headers

      expect(parsed_body["reply_message"]).to include("- You can check in from 15:00.")

      post path, params: { message: "no 2", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Please reply *Yes* to confirm the book and *No* to reconsider the choices.")
    end

    it "resumes the saved option set after a room information interruption" do
      room_type = seed_room_type_options("Executive Suite", month: 5, days: [ 21, 22, 23, 24, 25, 26 ])
      room_type.update!(
        description: "Large suite with sea view.",
        amenities: %w[wifi balcony]
      )

      post path, params: { message: "late may", phone: phone }.to_json, headers: headers
      post path, params: { message: "4 days 3 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "tell me about the executive suite", phone: phone }.to_json, headers: headers

      expect(parsed_body["reply_message"]).to include("Executive Suite: Large suite with sea view")

      post path, params: { message: "no 1", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Executive Suite")
      expect(parsed_body["reply_message"]).to include("Please reply *Yes* to confirm the book and *No* to reconsider the choices.")
    end

    # The catalogue is answered by number, and a room name is not a second way
    # in: it only ever guessed at which row was meant.
    it "asks for the number when the guest replies with just the room type name" do
      seed_room_type_options("Executive Penthouse", month: 6, days: [ 6, 7, 8, 9 ], max_adults: 3)
      seed_room_type_options("Garden Prestige Suite", month: 6, days: [ 6, 7, 8, 9 ], max_adults: 3)

      post path, params: { message: "hello, any booking for early june?", phone: phone }.to_json, headers: headers
      post path, params: { message: "5 days 4 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 adults 3 children", phone: phone }.to_json, headers: headers
      post path, params: { message: "can i chose executive penthouse", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Please reply with the number from the list")
      expect(parsed_body["reply_message"]).not_to include("Please reply *Yes* to confirm")
    end

    it "selects an option when the guest says i chose option 1" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 21, 22, 23 ])

      post path, params: { message: "hello, any booking for late august?", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 days 1 night", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "i chose option 1", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Garden Prestige Suite")
      expect(parsed_body["reply_message"]).to include("Please reply *Yes* to confirm the book and *No* to reconsider the choices.")
    end

    it "returns a booking url with total and expiry after yes" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 11, 12, 13, 14 ])

      post path, params: { message: "mid august", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 days 2 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "Garden Prestige Suite option 2", phone: phone }.to_json, headers: headers
      post path, params: { message: "yes", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Quotation link:")
      expect(parsed_body["reply_message"]).to include("Total:")
      expect(parsed_body["reply_message"]).to include("will expire")
      expect(parsed_body["action_name"]).to be_nil
      state = Prospect.lookup_by_phone(phone).first.prospect_conversation_state
      expect(state.flow_status).to eq("ended")
      expect(state.slots_payload.dig("conversation", "end_reason")).to eq("booking_url_generated")
    end

    it "returns a friendly fallback without completing the conversation when quote generation is stale" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 11, 12, 13, 14 ])

      post path, params: { message: "mid august", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 days 2 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "Garden Prestige Suite option 2", phone: phone }.to_json, headers: headers

      quote_service = instance_double(BookingEngine::CreateQuote, call: OpenStruct.new(success?: true, quote: nil))
      allow(BookingEngine::CreateQuote).to receive(:new).and_return(quote_service)

      post path, params: { message: "yes", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body.keys).to contain_exactly("reply_message", "needs_human_support", "action_name", "prospect_public_id")
      expect(parsed_body["reply_message"]).to eq("Unable to generate quote right now.")
      expect(parsed_body["needs_human_support"]).to be(true)
      expect(parsed_body["action_name"]).to be_nil

      prospect = Prospect.lookup_by_phone(phone).first

      # The web chat's job reads only `success?` and discards the payload, so a
      # reply that never becomes a message is a reply that guest never sees.
      expect(prospect.prospect_messages.where(direction: "outbound").last.body)
        .to eq("Unable to generate quote right now.")

      state = prospect.prospect_conversation_state
      expect(state.flow_status).not_to eq("ended")
      expect(state.slots_payload.dig("conversation", "end_reason")).not_to eq("booking_url_generated")
      expect(state.slots_payload.dig("booking_task", "status")).to eq("waiting_for_confirmation")
    end

    it "starts a fresh branch after another booking" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 11, 12, 13, 14 ])

      post path, params: { message: "mid august", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 days 2 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "Garden Prestige Suite option 2", phone: phone }.to_json, headers: headers
      post path, params: { message: "yes", phone: phone }.to_json, headers: headers

      expect(parsed_body["reply_message"]).to include("Quotation link:")

      post path, params: { message: "another booking", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("date or month")
      expect(parsed_body["reply_message"]).not_to include("Quotation link:")
      expect(parsed_body["reply_message"]).not_to include("Please reply *Yes* to confirm the book")
      expect(parsed_body["action_name"]).to eq("request_quote")
    end

    it "answers hotel amenities after a completed booking without room fallback" do
      hotel.update!(amenities: [ Hotel::HOTEL_AMENITIES.first.fetch(:id) ])
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 11, 12, 13, 14 ])

      post path, params: { message: "mid august", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 days 2 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "Garden Prestige Suite option 2", phone: phone }.to_json, headers: headers
      post path, params: { message: "yes", phone: phone }.to_json, headers: headers

      expect(parsed_body["reply_message"]).to include("Quotation link:")

      post path, params: { message: "may i know hotel amenities", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Available amenities include")
      expect(parsed_body["reply_message"]).not_to include("I couldn't match that room type")
    end

    it "returns 422 when concierge is disabled" do
      hotel.update!(ai_provider_enabled: false)

      post path, params: { message: "Hello", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(parsed_body["error"]).to eq("AI Concierge is not enabled for this hotel.")
    end

    it "returns 422 when phone and prospect public id are missing" do
      post path, params: { message: "Hello" }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(parsed_body["error"]).to eq("Phone or prospect_public_id is required for AI concierge conversations")
    end

    it "continues a conversation by prospect public id" do
      post path, params: { message: "hello, any booking for early august?", phone: phone }.to_json, headers: headers
      prospect_public_id = parsed_body["prospect_public_id"]

      post path, params: { message: "3 days 2 nights", prospect_public_id: prospect_public_id }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["prospect_public_id"]).to eq(prospect_public_id)
      expect(parsed_body["reply_message"]).to include("early August")
      expect(parsed_body["reply_message"]).to include("How many guests")
    end

    it "returns 404 for an invalid prospect public id" do
      post path, params: { message: "Hello", prospect_public_id: "prsp_missing" }.to_json, headers: headers

      expect(response).to have_http_status(:not_found)
      expect(parsed_body["error"]).to eq("Prospect not found")
    end

    it "ends and reactivates the same conversation state" do
      post path, params: { message: "Hello", phone: phone }.to_json, headers: headers
      prospect_public_id = parsed_body["prospect_public_id"]

      post path, params: { message: "stop", prospect_public_id: prospect_public_id }.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to eq("Thank you for chatting with us. Message us any time.")

      state = Prospect.find_by!(public_id: prospect_public_id).prospect_conversation_state
      expect(state.flow_status).to eq("ended")
      expect(state.slots_payload.dig("conversation", "end_reason")).to eq("user_ended")

      post path, params: { message: "hello, any booking for early august?", prospect_public_id: prospect_public_id }.to_json, headers: headers

      state.reload
      expect(response).to have_http_status(:ok)
      expect(state.flow_status).not_to eq("ended")
      expect(state.slots_payload.dig("conversation", "status")).to eq("active")
      expect(state.slots_payload.dig("conversation", "end_reason")).to be_nil
    end
  end

  # ReferenceClassifier decides every message here. It is deliberately stricter
  # than the private router this replaced: it extracts only what the sentence
  # states, so a guest who names a month gets asked for a duration instead of
  # having one invented for them.
  ROOM_VOCABULARY = [
    "Executive Suite", "Executive Penthouse", "Ocean Villa King", "Garden Prestige Suite", "Deluxe Room"
  ].freeze

  def stub_interpreter
    stub_concierge_model(room_type_names: ROOM_VOCABULARY)
  end

  def seed_room_type_options(room_type_name, month:, days:, max_adults: 2, base_price: 180)
    year = infer_year(month)
    room_type = create(:room_type, hotel: hotel, name: room_type_name, base_price: base_price, max_adults: max_adults)

    days.each_with_index do |day, index|
      date = Date.new(year, month, day)
      create(:room_rate, room_type: room_type, date: date, price: base_price + 40 + index, currency: "MYR")
      create(:room_inventory, room_type: room_type, date: date, quantity: 2, status: "open")
    end

    room_type
  end

  def infer_year(month)
    candidate = Date.new(Date.current.year, month, 1)
    candidate < Date.current.beginning_of_month ? Date.current.year + 1 : Date.current.year
  end

  def parsed_body
    JSON.parse(response.body)
  end
end
