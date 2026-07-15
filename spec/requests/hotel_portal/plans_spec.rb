require "rails_helper"

RSpec.describe "HotelPortal::Plans", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:plan) { create(:plan, name: "All Access") }
  let(:hotel) { create(:hotel, account: account, plan: plan) }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }
  let!(:included_group) { create(:feature_group, name: "Property Management System", position: 1) }
  let!(:empty_group) { create(:feature_group, name: "Empty Group", position: 2) }
  let!(:included_feature) { create(:feature, feature_group: included_group, name: "Reservations", slug: "reservations") }
  let!(:locked_feature) { create(:feature, feature_group: included_group, name: "Per pax booking", slug: "per_pax_booking") }
  let!(:included_plan_feature) { create(:plan_feature, plan: plan, feature: included_feature, enabled: true) }
  let!(:locked_plan_feature) { create(:plan_feature, plan: plan, feature: locked_feature, enabled: false) }

  before do
    manage_profile = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |permission| permission.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: manage_profile)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "renders the shared settings shell and split billing workspace" do
    get hotel_plan_path(hotel)

    expect(response).to have_http_status(:ok)
    document = response.parsed_body
    expect(document.css("h1").map { |heading| heading.text.squish }).to eq([ "General Hotel Settings" ])
    expect(document.at_css("[data-testid='plan-billing-layout']")).to be_present
    expect(document.at_css("[data-testid='plan-feature-card'].panel-card")).to be_present
    expect(document.at_css("[data-testid='plan-feature-scroll-area'].panel-scroll-area")).to be_present
    expect(document.at_css("[data-testid='settings-tabs']").text).to include("General", "Plan & Billing")
    expect(document.at_css(".panel-alert[data-actions-layout='stacked'] .panel-alert__actions .panel-button.w-full")).to be_present
  end

  it "shows included and locked features while omitting empty groups" do
    get hotel_plan_path(hotel)

    document = response.parsed_body
    expect(document.text).to include("Reservations", "Per pax booking", "Unlock 1 more feature")
    expect(document.text).not_to include("Empty Group")
    expect(document.at_css(".text-success")).to be_present
    expect(document.at_css(".text-muted-foreground").text).to be_present
  end

  it "shows the all-included success state without an upgrade action" do
    locked_plan_feature.update!(enabled: true)

    get hotel_plan_path(hotel)

    expect(response.body).to include("All features included")
    expect(response.body).not_to include("Contact us to upgrade")
  end
end
