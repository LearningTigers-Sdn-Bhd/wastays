require "rails_helper"

RSpec.describe "HotelPortal::NightAudits Force Roll", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, :without_current_business_date, account: account, plan: plan, status: "live") }
  let(:user) { create(:user, account: account, role: "hotel_staff") }
  let(:role) { create(:role, account: account, slug: "manager", name: "Manager") }
  let!(:manage_permission) { Permission.find_or_create_by!(slug: "manage_night_audit") { |p| p.name = "Manage Night Audit" } }
  let!(:override_permission) { Permission.find_or_create_by!(slug: "override_financial_date_lock") { |p| p.name = "Override Date Lock" } }

  before do
    role.permissions << manage_permission
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "no_show_auto_handling"), enabled: true)
  end

  def sign_in(current_user)
    post login_path, params: { email: current_user.email, password: current_user.password }
    follow_redirect!
  end

  context "when user has manage_night_audit but NOT override_financial_date_lock" do
    it "denies force roll request" do
      sign_in(user)
      business_date = 1.day.ago.to_date

      post hotel_night_audits_path(hotel), params: {
        night_audit: {
              business_date: business_date.to_s,
              force_roll: "1",
              notes: "Manager accepted unresolved blockers"
        }
      }

      expect(response).to redirect_to(hotel_night_audits_path(hotel))
      expect(flash[:alert]).to eq("You do not have permission to force-roll the night audit.")
    end
  end

  context "when user has override_financial_date_lock permission" do
    before do
      role.permissions << override_permission
    end

    it "allows force roll and enqueues the job with force_roll: true" do
      sign_in(user)
      business_date = 1.day.ago.to_date

      expect {
        post hotel_night_audits_path(hotel), params: {
          night_audit: {
            business_date: business_date.to_s,
            force_roll: "1",
            notes: "Manager accepted unresolved blockers"
          }
        }
      }.to have_enqueued_job(NightAudits::RunJob).with(
        anything, # night_audit_id
        user.id,
        hash_including(force_roll: true)
      )

      expect(response).to redirect_to(hotel_night_audit_path(hotel, NightAudit.last))
      expect(NightAudit.last.force_closed).to be(true)
    end
  end
end
