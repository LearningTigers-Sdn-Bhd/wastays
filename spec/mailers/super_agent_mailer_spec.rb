# frozen_string_literal: true

require "rails_helper"

RSpec.describe SuperAgentMailer do
  let(:agent) { create(:user, :super_agent, email: "aina@agent.test") }
  let(:hotel) { create(:hotel, name: "Luma Stay", created_by_user: agent) }

  describe "#hotel_registered" do
    it "tells the agent which hotel used their code" do
      owner = create(:user, account: hotel.account, name: "Hana Lim")
      create(:user_hotel_access, user: owner, hotel:, role: create(:role, account: hotel.account, slug: "hotel_owner"))

      email = described_class.hotel_registered(hotel)

      expect(email.to).to eq([ "aina@agent.test" ])
      expect(email.subject).to eq("Luma Stay registered with your invite link")
      expect(email.text_part.body.to_s).to include("Hana Lim registered Luma Stay", agent.agent_code, "/agent/hotels")
    end
  end

  describe "#onboarding_update" do
    SuperAgentMailer::UPDATES.each do |type, update|
      it "sends the #{type} update" do
        submission = create(:onboarding_submission, hotel:, submitted_by: create(:user, account: hotel.account))
        delivery = create(:onboarding_delivery, onboarding_submission: submission, delivery_type: type, recipient_email: "aina@agent.test")

        email = described_class.onboarding_update(delivery)

        expect(email.subject).to eq("Luma Stay: #{update[:subject]}")
        expect(email.text_part.body.to_s).to include("Status: #{update[:status]}", update[:next_step])
      end
    end
  end
end
