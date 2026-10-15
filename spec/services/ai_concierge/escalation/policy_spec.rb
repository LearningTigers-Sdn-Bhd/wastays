# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Escalation::Policy do
  let(:hotel) { create(:hotel) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation) { create(:conversation, hotel: hotel, prospect: prospect) }

  def decision(trigger, failure_count: 0)
    described_class.new(
      hotel: hotel,
      conversation: conversation,
      trigger: trigger,
      failure_count: failure_count
    ).call
  end

  it "always hands off emergencies and explicit requests for a person" do
    expect(decision("emergency")).to be_handoff
    expect(decision("guest_asks_for_person")).to be_handoff
  end

  it "hands off enabled optional triggers immediately" do
    create(
      :hotel_guest_contact,
      hotel: hotel,
      escalation_triggers: %w[complaint booking_change payment_question]
    )

    expect(decision("complaint")).to be_handoff
    expect(decision("booking_change")).to be_handoff
    expect(decision("payment_question")).to be_handoff
  end

  it "does not hand off disabled optional triggers" do
    create(:hotel_guest_contact, hotel: hotel, escalation_triggers: [])

    expect(decision("complaint")).not_to be_handoff
    expect(decision("booking_change")).not_to be_handoff
    expect(decision("payment_question")).not_to be_handoff
  end

  it "hands off no-answer exactly at the configured threshold" do
    create(:hotel_guest_contact, hotel: hotel, escalation_triggers: [ "no_answer" ], escalation_attempts: 2)

    expect(decision("no_answer", failure_count: 1)).not_to be_handoff
    expect(decision("no_answer", failure_count: 2)).to be_handoff
  end

  it "never hands off no-answer when that trigger is disabled" do
    create(:hotel_guest_contact, hotel: hotel, escalation_triggers: [], escalation_attempts: 1)

    expect(decision("no_answer", failure_count: 5)).not_to be_handoff
  end

  it "does not produce another handoff after staff have already been requested" do
    create(:hotel_guest_contact, hotel: hotel, escalation_triggers: [ "complaint" ])
    conversation.request_human!(at: Time.zone.parse("2026-09-28 10:00:00"))

    expect(decision("complaint")).not_to be_handoff
    expect(decision("complaint").message).to be_nil
  end
end
