require "rails_helper"

RSpec.describe "HotelPortal::NightAudits", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "live") }
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

    post hotel_night_audits_path(hotel), params: {
      night_audit: {
        business_date: business_date.to_s,
        notes: "Run now"
      }
    }

    expect(response).to redirect_to(hotel_night_audit_path(hotel, NightAudit.last))
    expect(flash[:notice]).to eq("Night audit completed successfully.")
    expect(NightAudit.last.business_date).to eq(business_date)
    expect(NightAudit.last.trigger_mode).to eq("manual")
  end

  it "defaults manual business date to yesterday when omitted" do
    sign_in(user)

    post hotel_night_audits_path(hotel), params: { night_audit: { notes: "Default run" } }

    yesterday_kl = Time.use_zone(User::DEFAULT_TIME_ZONE) { Date.current - 1.day }
    expect(NightAudit.last.business_date).to eq(yesterday_kl)
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
    post hotel_night_audits_path(hotel), params: {
      night_audit: {
        business_date: today_kl.to_s
      }
    }

    expect(response).to redirect_to(hotel_night_audit_path(hotel, NightAudit.last))
    expect(flash[:alert]).to eq("Night audit completed with blockers.")
    expect(NightAudit.last).to be_blocked
  end
end
