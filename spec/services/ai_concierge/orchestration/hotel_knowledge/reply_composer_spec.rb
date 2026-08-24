# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Orchestration::HotelKnowledge::ReplyComposer do
  let(:reply_class) { AiConcierge::Orchestration::HotelKnowledge::Reply }

  def fact(text, topic: nil)
    reply_class::Fact.new(topic: topic, text: text)
  end

  def compose(shape:, facts: [], missing_topic: nil, remaining_topics: [], tone: "basic")
    reply = reply_class.new(
      shape: shape,
      answer_mode: shape == "unavailable" ? "unavailable" : "structured",
      facts: facts,
      missing_topic: missing_topic,
      remaining_topics: remaining_topics,
      success: shape != "unavailable"
    )
    described_class.new(reply: reply, tone: tone).call
  end

  it "keeps a narrow answer to two sentences and removes common filler" do
    message = compose(
      shape: "direct",
      facts: [
        fact("Thank you for your inquiry! Check-in starts at 3:00 PM. Check-out is at 11:00 AM. Please let us know if you need help.")
      ]
    )

    expect(message).to eq("Check-in starts at 3:00 PM. Check-out is at 11:00 AM.")
  end

  it "renders even one broad fact as a bullet" do
    message = compose(shape: "list", facts: [ fact("Check-in starts at 3:00 PM.", topic: "check-in") ])

    expect(message).to eq("Here are the available details:\n- Check-in starts at 3:00 PM.")
  end

  it "renders no more than five bullets and mentions remaining topics" do
    facts = (1..6).map { |index| fact("Fact #{index}.", topic: "topic #{index}") }

    message = compose(shape: "list", facts: facts, remaining_topics: [ "topic 6", "late arrival" ])

    expect(message.lines.count { |line| line.start_with?("- ") }).to eq(5)
    expect(message).to include("You can also ask about topic 6 or late arrival.")
    expect(message).not_to include("Fact 6.")
  end

  it "uses useful topic-specific unavailable replies" do
    expect(compose(shape: "unavailable", missing_topic: "service information"))
      .to eq("The hotel has not listed that service yet. Please ask the front desk for the current details.")
    expect(compose(shape: "unavailable", missing_topic: "nearby attractions"))
      .to eq("The hotel has not listed nearby attractions yet. Please ask the front desk for local recommendations.")
    expect(compose(shape: "unavailable", missing_topic: "room type"))
      .to eq("I could not match that room type. Please send the room type name.")
    expect(compose(shape: "unavailable", missing_topic: "an FAQ answer"))
      .to eq("I could not find that answer in the hotel's FAQ. Please ask the front desk for the current details.")
    expect(compose(shape: "unavailable", missing_topic: "policy information"))
      .to eq("The hotel has not added that policy yet. Please ask the front desk for the current details.")
  end

  it "asks one focused clarification question" do
    message = compose(
      shape: "clarification",
      facts: [ fact("Which policy would you like to know about: check-in, check-out, cancellation, or house rules?") ]
    )

    expect(message).to eq("Which policy would you like to know about: check-in, check-out, cancellation, or house rules?")
  end

  it "does not repeat a fact from the previous reply when the guest asks what else" do
    reply = reply_class.new(
      shape: "direct",
      answer_mode: "synthesized",
      facts: [
        fact("Pets are not allowed.", topic: "pets"),
        fact("Smoking is prohibited in all indoor areas.", topic: "smoking")
      ],
      success: true
    )

    message = described_class.new(
      reply: reply,
      message: "what else is restricted?",
      previous_reply: "Pets are not allowed."
    ).call

    expect(message).to eq("Smoking is prohibited in all indoor areas.")
  end

  it "states that no new restriction was found when every selected fact was already given" do
    reply = reply_class.new(
      shape: "direct",
      answer_mode: "deterministic",
      facts: [ fact("Pets are not allowed.", topic: "pets") ],
      success: true
    )

    message = described_class.new(
      reply: reply,
      message: "what else is restricted?",
      previous_reply: "Pets are not allowed."
    ).call

    expect(message).to eq("I could not find another listed restriction.")
  end

  it "keeps business replies formal without greetings, contractions, or exclamation marks" do
    message = compose(
      shape: "list",
      facts: [ fact("We're open all day!"), fact("Pets can't enter the restaurant!") ],
      tone: "business"
    )

    expect(message).to start_with("The available details are:")
    expect(message).not_to match(/thank you|welcome|please let us know/i)
    expect(message).not_to include("'", "!")
    expect(message).to include("we are open all day.", "Pets cannot enter the restaurant.")
  end

  it "adds only light in-answer warmth for cheerful lists" do
    message = compose(shape: "list", facts: [ fact("Parking is free."), fact("Wi-Fi is available.") ], tone: "cheerful")

    expect(message).to start_with("Here are the details we have:")
    expect(message).not_to match(/thank you|welcome|let us know|happy to help/i)
  end
end
