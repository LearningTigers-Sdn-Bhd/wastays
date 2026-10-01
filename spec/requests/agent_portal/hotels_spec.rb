# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AgentPortal::Hotels", type: :request do
  let(:token) { SecureRandom.hex(6) }
  let(:platform_account) { create(:account, name: "Platform #{token}") }
  let(:agent) { create(:user, :super_agent, account: platform_account, can_create_hotels: true) }
  let!(:enterprise) { Plan.find_by(slug: "enterprise") || create(:plan, name: "Enterprise", slug: "enterprise") }
  let(:hotel_params) do
    {
      agent_portal_hotels_create_form: {
        account_name: "Luma Hospitality Group",
        owner_name: "Hotel Owner",
        owner_email: "owner-#{token}@lumastay.test",
        hotel_name: "Luma Stay",
        sell_mode: "per_room"
      }
    }
  end

  describe "access" do
    it "keeps other roles out" do
      sign_in_as(create(:user, :superadmin, account: platform_account))

      get agent_hotels_path

      expect(response).to redirect_to(root_path)
    end

    it "keeps super agents out of the admin portal" do
      sign_in_as(agent)

      get admin_hotels_path

      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /agent/hotels" do
    before { sign_in_as(agent) }

    it "lists only the hotels the agent created" do
      create(:hotel, name: "Mine #{token}", created_by_user: agent)
      create(:hotel, name: "Other #{token}")

      get agent_hotels_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mine #{token}")
      expect(response.body).not_to include("Other #{token}")
    end

    it "opens each hotel in a new tab" do
      hotel = create(:hotel, created_by_user: agent)

      get agent_hotels_path

      link = Nokogiri::HTML(response.body).at_css("a[href=\"#{hotel_dashboard_path(hotel)}\"]")
      expect(link["target"]).to eq("_blank")
      expect(link["rel"]).to eq("noopener")
    end
  end

  describe "GET /agent/hotels/new" do
    before { sign_in_as(agent) }

    it "shows only the agent fields" do
      get new_agent_hotel_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Hotel name")
      expect(response.body).not_to include("Subscription plan")
      expect(response.body).not_to include("Preferred channel manager")
      expect(response.body).not_to include("Internal salesperson")
      expect(response.body).not_to include("Boat features")
      expect(response.body).not_to include("Hide payout reports")
    end
  end

  describe "POST /agent/hotels" do
    before { sign_in_as(agent) }

    it "creates the hotel with the fixed platform choices" do
      expect {
        post agent_hotels_path, params: hotel_params
      }.to change(Hotel, :count).by(1).and change(StaffInvitation, :count).by(0)

      hotel = Hotel.order(:created_at).last

      expect(response).to redirect_to(agent_hotels_path)
      expect(hotel).to have_attributes(
        plan: enterprise,
        preferred_channel_manager: "undecided",
        salesperson_id: nil,
        allow_boat_information: false,
        hide_payout_reports: true,
        created_by_user: agent
      )
    end

    it "ignores platform choices sent in the request" do
      other_plan = create(:plan)
      salesperson = create(:user, :salesperson, account: platform_account)
      crafted = hotel_params.deep_dup
      crafted[:agent_portal_hotels_create_form].merge!(
        plan_id: other_plan.id, salesperson_id: salesperson.id, allow_boat_information: "1", hide_payout_reports: "0"
      )

      post agent_hotels_path, params: crafted

      hotel = Hotel.order(:created_at).last
      expect(hotel).to have_attributes(plan: enterprise, salesperson_id: nil, allow_boat_information: false, hide_payout_reports: true)
    end

    it "gives the owner a usable password and the agent General Manager access" do
      post agent_hotels_path, params: hotel_params

      hotel = Hotel.order(:created_at).last
      owner = User.find_by(email: "owner-#{token}@lumastay.test")
      password = flash[:owner_credentials]["password"]

      expect(owner.authenticate(password)).to eq(owner)
      expect(agent.user_hotel_accesses.find_by(hotel: hotel).role.slug).to eq("general_manager")
    end

    it "shows the sign-in details once after creation" do
      post agent_hotels_path, params: hotel_params
      follow_redirect!

      expect(response.body).to include("Owner sign-in details")
      expect(response.body).to include("owner-#{token}@lumastay.test")
      expect(response.body).to include(login_url)
    end

    it "uses the owner password the agent typed" do
      hotel_params[:agent_portal_hotels_create_form][:owner_password] = "owner-pass-1"

      post agent_hotels_path, params: hotel_params

      owner = User.find_by(email: "owner-#{token}@lumastay.test")
      expect(owner.authenticate("owner-pass-1")).to eq(owner)
      expect(flash[:owner_credentials]["password"]).to eq("owner-pass-1")
    end

    it "rejects an owner password shorter than 8 characters" do
      hotel_params[:agent_portal_hotels_create_form][:owner_password] = "short"

      expect {
        post agent_hotels_path, params: hotel_params
      }.not_to change(Hotel, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Owner password is too short")
    end

    it "re-renders the form when a field is missing" do
      hotel_params[:agent_portal_hotels_create_form].delete(:sell_mode)

      expect {
        post agent_hotels_path, params: hotel_params
      }.not_to change(Hotel, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end

RSpec.describe "AgentPortal hotel access", type: :request do
  let(:agent) { create(:user, :super_agent, can_create_hotels: true) }

  before do
    Plan.find_by(slug: "enterprise") || create(:plan, name: "Enterprise", slug: "enterprise")
    Permission.find_or_create_by!(slug: "manage_hotel_profile") { |permission| permission.name = "Manage Hotel Profile" }
    sign_in_as(agent)
  end

  it "lets the agent open the hotel they created in the hotel portal" do
    post agent_hotels_path, params: {
      agent_portal_hotels_create_form: {
        account_name: "Luma Group", owner_name: "Owner", owner_email: "owner-access@lumastay.test",
        hotel_name: "Luma Stay", sell_mode: "per_room"
      }
    }
    hotel = agent.created_hotels.last

    get hotel_dashboard_path(hotel)
    follow_redirect! while response.redirect?

    expect(response).to have_http_status(:ok)
    expect(request.path).not_to include("setup_lock")
    expect(response.body).to include("Agent portal")
  end
end

RSpec.describe "AgentPortal hotel creation switch and invite", type: :request do
  let(:agent) { create(:user, :super_agent) }

  before { sign_in_as(agent) }

  it "blocks hotel creation by default and hides the Add hotel button" do
    get agent_hotels_path
    expect(response.body).not_to include(new_agent_hotel_path)

    get new_agent_hotel_path
    expect(response).to redirect_to(agent_hotels_path)

    expect {
      post agent_hotels_path, params: { agent_portal_hotels_create_form: { hotel_name: "Blocked" } }
    }.not_to change(Hotel, :count)
  end

  it "shows the invite link with the agent code" do
    get agent_hotels_path

    expect(response.body).to include("Invite a hotel")
    expect(response.body).to include(register_url(c: agent.agent_code))
  end
end
