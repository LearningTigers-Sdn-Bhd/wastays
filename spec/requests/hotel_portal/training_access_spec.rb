# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel portal training access", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:, status: "pending_review") }
  let(:role) { create(:role, account:) }
  let(:owner) { create(:user, account:) }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role:, permission:)
    create(:user_hotel_access, user: owner, hotel:, role:)
    sign_in_as(owner)
  end

  it "renders the normal PMS shell and a persistent training banner during review" do
    get hotel_dashboard_path(hotel)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-testid="training-mode-banner"')
    expect(response.body).to include("Property under review")
    expect(response.body).not_to include("Training mode")
    expect(response.body).to include("Search dashboard pages")
    expect(response.parsed_body.at_css(".panel-navbar__identity-meta").text.squish).to eq("ID #{hotel.unique_id}")
  end

  it "blocks submitted configuration writes by default" do
    patch hotel_property_policy_path(hotel), params: { property_policy: { cancellation_policy: "Changed" } }

    expect(response).to redirect_to(hotel_dashboard_path(hotel))
    expect(flash[:alert]).to eq("This setting is read-only while WAStays reviews your property.")
  end

  it "keeps the user's own profile writable" do
    patch hotel_user_profile_path(hotel), params: { user: { name: "Training Owner" } }

    expect(response).to redirect_to(edit_hotel_user_profile_path(hotel))
    expect(owner.reload.name).to eq("Training Owner")
  end

  context "after approval" do
    before { hotel.update!(status: "ready_to_launch") }

    it "shows the non-dismissible keep-or-reset decision" do
      get hotel_dashboard_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="training-decision-banner"')
      expect(response.body).to include("Continue with current data")
      expect(response.body).to include("Clear activity and start fresh")
      expect(response.body).not_to include("Dismiss banner")

      document = Nokogiri::HTML(response.body)
      keep = document.at_css("a[href='#{keep_hotel_training_decision_path(hotel)}']")
      reset = document.at_css("a[href='#{reset_hotel_training_decision_path(hotel)}']")
      expect(keep["data-turbo-method"]).to eq("post")
      expect(reset["data-turbo-method"]).to eq("post")
      expect(reset["data-turbo-confirm"]).to include("Clear all PMS activity")
    end

    it "makes PMS mutations read-only while awaiting a decision" do
      patch hotel_property_policy_path(hotel), params: { property_policy: { cancellation_policy: "Changed" } }

      expect(response).to redirect_to(hotel_dashboard_path(hotel))
      expect(flash[:alert]).to include("Choose whether to continue with or clear")
    end

    it "shows reset progress and keeps the PMS read-only" do
      hotel.update!(training_reset_state: "processing")

      get hotel_dashboard_path(hotel)

      expect(response.body).to include('data-testid="training-reset-progress-banner"')
      expect(response.body).to include("Clearing PMS activity")

      patch hotel_user_profile_path(hotel), params: { user: { name: "Blocked Name" } }

      expect(response).to redirect_to(hotel_dashboard_path(hotel))
      expect(owner.reload.name).not_to eq("Blocked Name")
      expect(flash[:alert]).to eq("The PMS is read-only while its activity is being cleared.")
    end

    it "shows retry and keep actions after a rolled-back reset failure" do
      hotel.update!(training_reset_state: "failed")

      get hotel_dashboard_path(hotel)

      expect(response.body).to include('data-testid="training-reset-failed-banner"')
      expect(response.body).to include("Retry reset")
      expect(response.body).to include("Continue with current data")
    end
  end
end
