# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::ConversationPresenter do
  let(:hotel) { build_stubbed(:hotel, unique_id: "AURCR") }

  def presenter_for(conversation) = described_class.new(conversation, view: ActionController::Base.new.view_context)

  def whatsapp(last_guest_message_at:, status: "open")
    build_stubbed(
      :conversation, :whatsapp,
      hotel: hotel, status: status, last_guest_message_at: last_guest_message_at
    )
  end

  # WhatsApp stops carrying a free-form reply 24 hours after the guest last
  # wrote. The chip is how a reader sees that coming while scanning the list,
  # rather than after typing an answer nobody delivers.
  describe "the reply window chip" do
    it "counts down in whole hours" do
      badge = presenter_for(whatsapp(last_guest_message_at: 6.hours.ago - 30.minutes)).reply_window_badge

      expect(badge).to eq({ label: "17h left", variant: :neutral })
    end

    it "turns urgent as the window runs down" do
      badge = presenter_for(whatsapp(last_guest_message_at: 21.hours.ago)).reply_window_badge

      expect(badge[:variant]).to eq(:warning)
    end

    # "0h left" reads like nothing at all, and there is still time to answer.
    it "says under an hour rather than counting zero" do
      badge = presenter_for(whatsapp(last_guest_message_at: 23.hours.ago - 30.minutes)).reply_window_badge

      expect(badge).to eq({ label: "Under 1h left", variant: :warning })
    end

    it "says so once the window has closed" do
      badge = presenter_for(whatsapp(last_guest_message_at: 25.hours.ago)).reply_window_badge

      expect(badge).to eq({ label: "Reply window closed", variant: :destructive })
    end

    # Most rows have no clock, and a chip on every one of them would stop
    # meaning "this one is running out".
    it "says nothing about a web thread" do
      thread = build_stubbed(:conversation, hotel: hotel, channel: "web", last_guest_message_at: 3.years.ago)

      expect(presenter_for(thread).reply_window_badge).to be_nil
    end

    it "says nothing about a thread the guest has never written on" do
      expect(presenter_for(whatsapp(last_guest_message_at: nil)).reply_window_badge).to be_nil
    end

    # Nobody is about to reply into a closed thread, so the clock is noise.
    it "says nothing once the thread is closed" do
      thread = whatsapp(last_guest_message_at: 2.hours.ago, status: "closed")

      expect(presenter_for(thread).reply_window_badge).to be_nil
    end
  end
end
