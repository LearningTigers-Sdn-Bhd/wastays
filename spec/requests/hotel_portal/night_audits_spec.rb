require "rails_helper"

RSpec.describe "HotelPortal::NightAudits", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:hotel) do
    create(:hotel,
      account: account,
      status: "live",
      time_zone: "Kuala Lumpur",
      business_starts_at: "08:00",
      business_ends_at: "02:00",
      arrival_grace_period: 7200)
  end
  let(:user) { create(:user, account: account, role: "hotel_staff") }
  let(:role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }
  let!(:permission) do
    Permission.find_or_create_by!(slug: "manage_night_audit") do |record|
      record.name = "Manage Night Audit"
    end
  end

  before do
    role.permissions << permission
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
  end

  def sign_in(current_user)
    post login_path, params: { email: current_user.email, password: current_user.password }
    follow_redirect!
  end

  it "allows front desk to create a night audit" do
    sign_in(user)
    today_kl = Time.use_zone(User::DEFAULT_TIME_ZONE) { Date.current }
    business_date = today_kl - 1.day

    perform_enqueued_jobs do
      post hotel_night_audits_path(hotel), params: {
        night_audit: {
          business_date: business_date.to_s,
          notes: "Run now"
        }
      }
    end

    expect(response).to redirect_to(hotel_night_audit_path(hotel, NightAudit.last))
    expect(flash[:notice]).to eq("Night audit has been scheduled in the background. Please wait while it processes.")
    expect(NightAudit.last.business_date).to eq(business_date)
    expect(NightAudit.last.trigger_mode).to eq("manual")
    expect(NightAudit.last).to be_completed
  end

  it "defaults manual business date to yesterday when omitted" do
    sign_in(user)

    kl_zone = Time.find_zone("Kuala Lumpur")
    travel_to(kl_zone.local(2026, 5, 19, 10, 10)) do
      # At 10:10 AM on May 19, May 18 should be the latest closable date
      expect(hotel.latest_closable_business_date).to eq(Date.new(2026, 5, 18))
      perform_enqueued_jobs do
        post hotel_night_audits_path(hotel), params: { night_audit: { notes: "Default run" } }
      end
    end

    expect(NightAudit.last.business_date).to eq(Date.new(2026, 5, 18))
    expect(NightAudit.last.trigger_mode).to eq("manual")
  end

  it "blocks access without permission" do
    role.permissions.delete(permission)
    sign_in(user)

    today_kl = Time.use_zone(User::DEFAULT_TIME_ZONE) { Date.current }
    post hotel_night_audits_path(hotel), params: {
      night_audit: {
        business_date: today_kl.to_s
      }
    }

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(flash[:alert]).to include("not authorized")
  end

  it "returns an alert redirect for a blocked audit" do
    sign_in(user)
    today_kl = Time.use_zone(User::DEFAULT_TIME_ZONE) { Date.current }
    create(:booking,
      hotel: hotel,
      status: "checked_in",
      payment_status: "captured",
      check_in: today_kl - 1.day,
      check_out: today_kl,
      checked_in_at: 1.day.ago)

    today_kl = Time.use_zone(User::DEFAULT_TIME_ZONE) { Date.current }
    perform_enqueued_jobs do
      post hotel_night_audits_path(hotel), params: {
        night_audit: {
          business_date: today_kl.to_s
        }
      }
    end

    expect(response).to redirect_to(hotel_night_audit_path(hotel, NightAudit.last))
    expect(flash[:notice]).to eq("Night audit has been scheduled in the background. Please wait while it processes.")
    expect(NightAudit.last).to be_blocked
  end

  it "does not enqueue another job for a pending audit" do
    sign_in(user)
    business_date = Date.new(2026, 5, 18)
    night_audit = create(:night_audit, hotel: hotel, business_date: business_date, status: "pending")

    expect do
      post hotel_night_audits_path(hotel), params: { night_audit: { business_date: business_date.to_s } }
    end.not_to have_enqueued_job(HotelOps::RunNightAuditJob)

    expect(response).to redirect_to(hotel_night_audit_path(hotel, night_audit))
    expect(flash[:notice]).to eq("Night audit is already scheduled or running in the background.")
  end
end
