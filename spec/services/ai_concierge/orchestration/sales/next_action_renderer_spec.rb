require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Sales::NextActionRenderer do
  def render(kind, intent: "hotel_information", missing_topic: nil, acknowledge_refusal: false, answer: "The hotel has a pool.")
    described_class.new(
      answer: answer,
      next_action: AiConcierge::Orchestration::Sales::NextAction.new(kind),
      intent: intent,
      missing_topic: missing_topic,
      acknowledge_refusal: acknowledge_refusal
    ).call
  end

  it "renders every action kind after the factual answer" do
    expect(render("offer_booking_help")).to end_with("Would you like me to help you find a room for your travel dates?")
    expect(render("offer_price_search")).to end_with("Would you like me to check prices for this room for your travel dates?")
    expect(render("offer_guided_hotel_exploration")).to end_with("What matters most for your stay: facilities, location, or room choices?")
    expect(render("resume_booking")).to end_with("Would you like to continue your booking?")
    expect(render("continue_booking")).to end_with("Would you like to continue your booking?")
    expect(render("offer_alternative_search")).to end_with("Would you like me to search another date or room?")
    expect(render("offer_front_desk")).to end_with("Please ask the front desk for assistance.")
    expect(render("none")).to eq("The hotel has a pool.")
  end

  it "uses conditional booking copy after a policy answer" do
    expect(render("offer_booking_help", intent: "hotel_policy"))
      .to end_with("If this policy works for you, I can help you find a room for your travel dates.")
  end

  it "uses topic-specific front-desk guidance" do
    expect(render("offer_front_desk", missing_topic: "nearby attractions"))
      .to end_with("Please ask the front desk for local recommendations.")
    expect(render("offer_front_desk", missing_topic: "service information"))
      .to end_with("Please ask the front desk for the current details.")
  end

  it "acknowledges a refusal before the answer and keeps one action" do
    message = render("none", acknowledge_refusal: true, answer: "Check-out is by 11:00 AM.")

    expect(message).to eq("No problem. Check-out is by 11:00 AM.")
  end
end
