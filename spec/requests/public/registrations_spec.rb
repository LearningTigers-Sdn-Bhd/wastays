# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public::Registrations", type: :request do
  let!(:enterprise) { Plan.find_by(slug: "enterprise") || create(:plan, name: "Enterprise", slug: "enterprise") }
  let(:agent) { create(:user, :super_agent, name: "Aina Agent") }
  let(:params) do
    {
      account: { name: "Luma Group" },
      hotel: { name: "Luma Stay", city: "Kuala Lumpur", country: "Malaysia", sell_mode: "per_room" },
      user: { name: "Owner", email: "owner-#{SecureRandom.hex(4)}@lumastay.test", password: "password123", password_confirmation: "password123" }
    }
  end

  it "shows who invited the hotel and keeps the code in the form" do
    get register_path(c: agent.agent_code.downcase)

    expect(response.body).to include("Invited by")
    expect(response.body).to include("Aina Agent")
    expect(Nokogiri::HTML(response.body).at_css("input[name=c]")["value"]).to eq(agent.agent_code)
  end

  it "links a hotel that registers with an invite code to the agent" do
    post register_path, params: params.merge(c: agent.agent_code)

    hotel = Hotel.order(:created_at).last
    expect(hotel).to have_attributes(
      created_by_user: agent, plan: enterprise, allow_boat_information: false, hide_payout_reports: true
    )
    expect(agent.user_hotel_accesses.find_by(hotel: hotel).role.slug).to eq("general_manager")
  end

  it "emails the agent when a hotel registers with their code" do
    expect {
      post register_path, params: params.merge(c: agent.agent_code)
    }.to have_enqueued_mail(SuperAgentMailer, :hotel_registered)
  end

  it "registers as normal when the code is unknown" do
    post register_path, params: params.merge(c: "NOPE99")

    hotel = Hotel.order(:created_at).last
    expect(hotel.created_by_user).to be_nil
    expect(hotel.plan).to be_nil
    expect(enqueued_jobs.map { |job| job["arguments"]&.first }).not_to include("SuperAgentMailer")
  end
end
