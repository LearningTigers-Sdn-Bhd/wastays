# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel onboarding shell", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "setup") }
  let(:user) { create(:user, account: account) }
  let(:role) { create(:role, account: account) }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "resolves the onboarding root to the first incomplete section" do
    get hotel_onboarding_path(hotel)

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "property_profile"))
    expect(hotel.onboarding_sections.count).to eq(13)
  end

  it "renders the dedicated shell with accessible phase navigation" do
    get hotel_onboarding_section_path(hotel, section_key: "property_profile")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Onboarding progress")
    expect(response.body).to include("Property profile")
    expect(response.body).to include("Save draft")
    expect(response.body).not_to include("Open navigation")
  end

  it "redirects a locked deep link to the earliest unmet prerequisite" do
    get hotel_onboarding_section_path(hotel, section_key: "taxes_fees")

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "property_profile"))
    follow_redirect!
    expect(response.body).to include("Complete the earlier onboarding steps")
  end

  it "saves a draft without completing the section" do
    patch hotel_onboarding_section_path(hotel, section_key: "property_profile"),
          params: { navigation_action: "save_draft" }

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "property_profile"))
    expect(hotel.onboarding_sections.find_by!(section_key: "property_profile").state).to eq("in_progress")
  end

  it "saves and advances to the next available step" do
    patch hotel_onboarding_section_path(hotel, section_key: "property_profile"),
          params: { navigation_action: "save_continue" }

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "roles_permissions"))
    section = hotel.onboarding_sections.find_by!(section_key: "property_profile")
    expect(section).to have_attributes(state: "complete", decision_metadata: include("placeholder" => true))
  end

  it "allows optional steps to be explicitly skipped" do
    hotel.onboarding_sections.create!(section_key: "property_profile", state: "complete")
    hotel.onboarding_sections.create!(section_key: "roles_permissions", state: "complete")

    patch hotel_onboarding_section_path(hotel, section_key: "staff_setup"),
          params: { navigation_action: "skip" }

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "taxes_fees"))
    expect(hotel.onboarding_sections.find_by!(section_key: "staff_setup").state).to eq("skipped")
  end

  it "keeps pending-review onboarding read-only" do
    hotel.update!(status: "pending_review")

    patch hotel_onboarding_section_path(hotel, section_key: "property_profile"),
          params: { navigation_action: "save_draft" }

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "property_profile"))
    expect(hotel.onboarding_sections.find_by!(section_key: "property_profile").state).to eq("not_started")

    follow_redirect!
    expect(response.body).to include("Setup submitted for review")
    expect(response.body).not_to include("Save draft")
  end

  it "presents requested changes in the affected section" do
    Onboarding::InitializeProgress.new(hotel: hotel).call
    hotel.onboarding_sections.find_by!(section_key: "property_profile").update!(state: "needs_attention")
    hotel.onboarding_audit_events.create!(
      user: user,
      event_type: "changes_requested",
      section_key: "property_profile",
      metadata: { explanation: "Add a clear exterior photo." },
      occurred_at: Time.current
    )

    get hotel_onboarding_section_path(hotel, section_key: "property_profile")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Changes requested")
    expect(response.body).to include("Add a clear exterior photo.")
  end

  it "does not expose another hotel's onboarding" do
    other_hotel = create(:hotel, status: "setup")

    get hotel_onboarding_path(other_hotel)

    expect(response).to redirect_to(root_path)
  end
end
