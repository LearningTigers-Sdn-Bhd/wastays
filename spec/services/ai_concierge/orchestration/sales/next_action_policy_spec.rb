require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Sales::NextActionPolicy do
  def policy(intent: "hotel_information", topic: nil, outcome: "answered", booking_task: {}, resumable_booking: false,
             needs_human_support: false, suppress_offer: false)
    described_class.new(
      intent: intent,
      topic: topic,
      outcome: outcome,
      booking_task: booking_task,
      resumable_booking: resumable_booking,
      needs_human_support: needs_human_support,
      suppress_offer: suppress_offer
    )
  end

  def kind(**arguments) = policy(**arguments).call.kind

  it "gives human support the highest priority" do
    expect(kind(outcome: "clarification", needs_human_support: true)).to eq("offer_front_desk")
  end

  it "does not add an action to a clarification" do
    expect(kind(outcome: "clarification", resumable_booking: true)).to eq("none")
  end

  it "resumes a suspended booking after an information answer" do
    expect(kind(intent: "hotel_policy", resumable_booking: true)).to eq("resume_booking")
  end

  it "offers another search when no booking option is available" do
    expect(kind(intent: "booking_search", outcome: "no_options", booking_task: active_task)).to eq("offer_alternative_search")
  end

  it "continues a booking that has an open question" do
    expect(kind(intent: "booking_search", outcome: "booking_progress", booking_task: active_task)).to eq("continue_booking")
  end

  it "does not continue a suspended booking as if it were active" do
    task = active_task.merge("status" => "suspended")

    expect(kind(outcome: "unavailable", booking_task: task, resumable_booking: true)).to eq("offer_front_desk")
  end

  it "offers the front desk when hotel information is unavailable" do
    expect(kind(outcome: "unavailable")).to eq("offer_front_desk")
  end

  it "offers a price search after a room-information answer" do
    expect(kind(intent: "room_information")).to eq("offer_price_search")
  end

  it "offers guided exploration after a broad hotel overview" do
    expect(kind(topic: "hotel_overview")).to eq("offer_guided_hotel_exploration")
  end

  it "offers booking help after general information" do
    %w[hotel_information hotel_policy nearby_attractions].each do |intent|
      expect(kind(intent: intent)).to eq("offer_booking_help")
    end
  end

  it "suppresses only optional sales offers" do
    expect(kind(suppress_offer: true)).to eq("none")
    expect(kind(intent: "room_information", suppress_offer: true)).to eq("none")
    expect(kind(topic: "hotel_overview", suppress_offer: true)).to eq("none")
    expect(kind(intent: "booking_search", outcome: "no_options", suppress_offer: true)).to eq("offer_alternative_search")
    expect(kind(intent: "booking_search", outcome: "booking_progress", booking_task: active_task, suppress_offer: true)).to eq("continue_booking")
    expect(kind(outcome: "unavailable", suppress_offer: true)).to eq("offer_front_desk")
  end

  it "does not mutate the booking task" do
    task = active_task
    original = task.deep_dup

    policy(intent: "booking_search", outcome: "booking_progress", booking_task: task, resumable_booking: false).call

    expect(task).to eq(original)
  end

  it "returns none for unsupported and completed contexts" do
    expect(kind(intent: "greeting")).to eq("none")
    expect(kind(intent: "booking_search", outcome: "completed")).to eq("none")
  end

  def active_task
    { "status" => "collecting_slots", "pending_question" => "booking_timing" }
  end
end
