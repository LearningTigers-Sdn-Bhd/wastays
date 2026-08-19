# frozen_string_literal: true

require "rails_helper"

RSpec.describe Concierge::PostStaffReply do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account, name: "Farah Idris") }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation) { create(:conversation, hotel: hotel, prospect: prospect, channel: "web") }

  def reply(body, on: conversation)
    described_class.new(conversation: on, user: user, body: body).call
  end

  it "files the reply against the thread and its author" do
    result = reply("We have parking, RM10 a night.")

    expect(result).to be_success
    expect(result.message.body).to eq("We have parking, RM10 a night.")
    expect(result.message.sender_role).to eq("staff")
    expect(result.message.sender_user).to eq(user)
    expect(result.message.direction).to eq("outbound")
  end

  # The decision the whole phase turns on: answering is taking the thread, so
  # the bot can never talk over someone who has already replied.
  it "takes the conversation over by the act of replying" do
    reply("We have parking.")

    expect(conversation.reload).to be_human
    expect(conversation.assigned_user).to eq(user)
  end

  it "announces the person before their first words, not after" do
    reply("We have parking.")

    roles = conversation.messages.reload.map(&:sender_role)
    expect(roles).to eq(%w[system staff])
  end

  it "does not announce anybody again on the second reply" do
    reply("First")
    reply("Second")

    expect(conversation.messages.reload.map(&:sender_role)).to eq(%w[system staff staff])
  end

  it "refuses an empty reply" do
    result = reply("   ")

    expect(result).not_to be_success
    expect(result.error).to include("Type a message")
    expect(conversation.messages.reload).to be_empty
  end

  it "refuses a reply longer than the limit" do
    result = reply("a" * (described_class::MAX_MESSAGE_LENGTH + 1))

    expect(result).not_to be_success
    expect(conversation.messages.reload).to be_empty
  end

  it "refuses to reply into a closed thread" do
    conversation.close!

    result = reply("Are you still there?")

    expect(result).not_to be_success
    expect(result.error).to include("closed")
  end

  # A reply nobody can deliver is worse than no reply box: staff believe they
  # have answered.
  it "refuses a channel the reply cannot travel down yet" do
    whatsapp = create(:conversation, hotel: hotel, prospect: create(:prospect, hotel: hotel), channel: "whatsapp")

    result = reply("We have parking.", on: whatsapp)

    expect(result).not_to be_success
    expect(result.error).to include("cannot be delivered")
    expect(whatsapp.messages.reload).to be_empty
  end
end
