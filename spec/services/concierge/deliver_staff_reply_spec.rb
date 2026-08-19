# frozen_string_literal: true

require "rails_helper"

RSpec.describe Concierge::DeliverStaffReply do
  let(:hotel) { create(:hotel, name: "Seaside", whatsapp_number: "+60111222333") }
  let(:prospect) { create(:prospect, hotel: hotel, phone_number: "+60123456789", name: "Aisyah") }
  let(:user) { create(:user, name: "Farah") }
  let!(:relay) do
    create(:webhook_endpoint, name: "Relay", hotel: hotel, event_types: [ described_class::EVENT ])
  end

  def conversation_on(channel)
    create(:conversation, hotel: hotel, prospect: prospect, channel: channel, mode: "human", assigned_user: user)
  end

  def staff_reply(conversation, body: "Checkout is at noon.")
    conversation.messages.create!(
      prospect: prospect, direction: "outbound", sender_role: "staff", sender_user: user, body: body
    )
  end

  describe "a staff reply on a WhatsApp thread" do
    it "is handed to the relay for that hotel" do
      conversation = conversation_on("whatsapp")

      expect { staff_reply(conversation) }
        .to have_enqueued_job(WebhookBroadcastJob)
        .with(described_class::EVENT, anything, hotel_id: hotel.id)
    end

    it "carries what the relay needs to send it" do
      conversation = conversation_on("whatsapp")
      captured = nil

      allow(WebhookBroadcastJob).to receive(:perform_later) { |_event, payload, **| captured = payload }

      message = staff_reply(conversation)

      expect(captured).to include(
        message_id: message.id,
        guest_phone: "+60123456789",
        guest_name: "Aisyah",
        hotel_whatsapp_number: "+60111222333",
        staff_name: "Farah",
        body: "Checkout is at noon."
      )
    end
  end

  describe "what it leaves alone" do
    # The guest's browser is already subscribed to the thread and had this
    # before the job could run.
    it "sends nothing for the web chat" do
      conversation = conversation_on("web")

      expect { staff_reply(conversation) }.not_to have_enqueued_job(WebhookBroadcastJob)
    end

    it "sends nothing for a message the guest wrote" do
      conversation = conversation_on("whatsapp")

      expect {
        conversation.messages.create!(prospect: prospect, direction: "inbound", sender_role: "guest", body: "Hello")
      }.not_to have_enqueued_job(WebhookBroadcastJob)
    end

    it "sends nothing for the system line announcing a handover" do
      conversation = conversation_on("whatsapp")

      expect {
        conversation.messages.create!(prospect: prospect, direction: "system", sender_role: "system", body: "Farah joined.")
      }.not_to have_enqueued_job(WebhookBroadcastJob)
    end

    it "sends nothing when no relay is connected for the hotel" do
      relay.destroy
      conversation = conversation_on("whatsapp")

      expect { staff_reply(conversation) }.not_to have_enqueued_job(WebhookBroadcastJob)
    end

    it "sends nothing when the relay belongs to another hotel" do
      relay.update!(hotel: create(:hotel))
      conversation = conversation_on("whatsapp")

      expect { staff_reply(conversation) }.not_to have_enqueued_job(WebhookBroadcastJob)
    end

    it "sends nothing when the guest has no number to send to" do
      prospect.update!(phone_number: nil)
      conversation = conversation_on("whatsapp")

      expect { staff_reply(conversation) }.not_to have_enqueued_job(WebhookBroadcastJob)
    end
  end
end
