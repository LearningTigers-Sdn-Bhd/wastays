require "rails_helper"

RSpec.describe "HotelPortal::NightAudits", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) do
    create(:hotel, :without_current_business_date,
      account: account,
      plan: plan,
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
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "no_show_auto_handling"), enabled: true)
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

  it "defaults manual business date to the current accounting date when omitted" do
    sign_in(user)

    kl_zone = Time.find_zone("Kuala Lumpur")
    travel_to(kl_zone.local(2026, 5, 19, 10, 10)) do
      # The clock still calculates May 18 as latest closable, but accounting authority remains May 19.
      expect(hotel.latest_closable_business_date).to eq(Date.new(2026, 5, 18))
      perform_enqueued_jobs do
        post hotel_night_audits_path(hotel), params: { night_audit: { notes: "Default run" } }
      end
    end

    expect(NightAudit.last.business_date).to eq(Date.new(2026, 5, 19))
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
    business_date = Time.use_zone(User::DEFAULT_TIME_ZONE) { Date.current - 1.day }
    create(:booking,
      hotel: hotel,
      status: "checked_in",
      payment_status: "captured",
      check_in: business_date - 1.day,
      check_out: business_date + 1.day,
      checked_in_at: 1.day.ago)

    perform_enqueued_jobs do
      post hotel_night_audits_path(hotel), params: {
        night_audit: {
          business_date: business_date.to_s
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
    end.not_to have_enqueued_job(NightAudits::RunJob)

    expect(response).to redirect_to(hotel_night_audit_path(hotel, night_audit))
    expect(flash[:notice]).to eq("Night audit is already scheduled or running in the background.")
  end

  it "rejects an unclosable business date before enqueueing a manual audit" do
    sign_in(user)
    kl_zone = Time.find_zone("Kuala Lumpur")

    travel_to(kl_zone.local(2026, 5, 21, 10, 0)) do
      expect do
        post hotel_night_audits_path(hotel), params: { night_audit: { business_date: Date.new(2026, 5, 21).to_s } }
      end.not_to have_enqueued_job(NightAudits::RunJob)
    end

    expect(response).to redirect_to(hotel_night_audits_path(hotel))
    expect(flash[:alert]).to include("cannot be audited yet")
    expect(NightAudit.where(hotel: hotel, business_date: Date.new(2026, 5, 21))).to be_empty
  end

  it "allows a development-only manual audit for an unclosed business date" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

    sign_in(user)
    kl_zone = Time.find_zone("Kuala Lumpur")

    travel_to(kl_zone.local(2026, 5, 21, 10, 0)) do
      perform_enqueued_jobs do
        post hotel_night_audits_path(hotel), params: {
          night_audit: {
            business_date: Date.new(2026, 5, 21).to_s,
            allow_unclosable_date: "1"
          }
        }
      end
    end

    expect(response).to redirect_to(hotel_night_audit_path(hotel, NightAudit.last))
    expect(NightAudit.last.business_date).to eq(Date.new(2026, 5, 21))
    expect(NightAudit.last).to be_completed
  end

  it "ignores the development-only override outside development" do
    sign_in(user)
    kl_zone = Time.find_zone("Kuala Lumpur")

    travel_to(kl_zone.local(2026, 5, 21, 10, 0)) do
      expect do
        post hotel_night_audits_path(hotel), params: {
          night_audit: {
            business_date: Date.new(2026, 5, 21).to_s,
            allow_unclosable_date: "1"
          }
        }
      end.not_to have_enqueued_job(NightAudits::RunJob)
    end

    expect(response).to redirect_to(hotel_night_audits_path(hotel))
    expect(flash[:alert]).to include("cannot be audited yet")
    expect(NightAudit.where(hotel: hotel, business_date: Date.new(2026, 5, 21))).to be_empty
  end

  describe "GET #resolve" do
    let(:night_audit) { create(:night_audit, hotel: hotel, status: "blocked") }

    it "renders the resolve page when the night audit is blocked" do
      sign_in(user)
      get resolve_hotel_night_audit_path(hotel, night_audit)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Resolve Audit Blockers")
    end

    it "redirects to show page when the night audit is not blocked" do
      night_audit.update!(status: "completed")
      sign_in(user)
      get resolve_hotel_night_audit_path(hotel, night_audit)
      expect(response).to redirect_to(hotel_night_audit_path(hotel, night_audit))
      expect(flash[:alert]).to eq("Night audit is not blocked.")
    end

    it "blocks access without permission" do
      role.permissions.delete(permission)
      sign_in(user)
      get resolve_hotel_night_audit_path(hotel, night_audit)
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET #blockers" do
    let(:night_audit) { create(:night_audit, hotel: hotel, status: "blocked") }

    it "returns the blockers as JSON" do
      sign_in(user)
      get blockers_hotel_night_audit_path(hotel, night_audit)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to have_key("blocked_details")
      expect(json).to have_key("exceptions")
    end

    it "blocks access without permission" do
      role.permissions.delete(permission)
      sign_in(user)
      get blockers_hotel_night_audit_path(hotel, night_audit)
      expect(response).to redirect_to(root_path)
    end
  end

  it "shows structured run results on the audit page" do
    night_audit = create(:night_audit,
      hotel: hotel,
      summary: {
        "run_results" => {
          "status_changes" => { "count" => 1, "items" => [] },
          "charges_posted" => { "count" => 2, "items" => [] },
          "skipped_items" => { "count" => 3, "items" => [] },
          "failed_items" => { "count" => 0, "items" => [] }
        }
      })
    create(:night_audit_financial_summary, night_audit: night_audit)
    sign_in(user)

    get hotel_night_audit_path(hotel, night_audit)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Run Results", "Status Changes", "Charges Posted", "Skipped Items", "Failed Items")
  end

  it "appends the active index and show tabs to the breadcrumbs" do
    night_audit = create(:night_audit, hotel: hotel)
    sign_in(user)

    get hotel_night_audits_path(hotel, tab: "advanced-actions")
    expect(response.body).to include("data-tab-breadcrumb-label>Advanced Actions</span>")
    expect(response.body).to include(%(href="#{hotel_night_audits_path(hotel)}">Night Audit</a>))
    expect(response.body).to include("aria-label=\"Open Night Audit navigation\"")

    get hotel_night_audit_path(hotel, night_audit, tab: "financial-summary")
    expect(response.body).to include("data-tab-breadcrumb-label>Financial Summary</span>")
  end

  it "separates hard blockers from warnings and makes close readiness obvious" do
    night_audit = create(:night_audit,
      hotel: hotel,
      status: "blocked",
      blocked_details: {
        "missing_folio" => [ { "guest_name" => "Aisha Tan", "confirmation_token" => "BLOCK-1", "reason" => "Booking requires a folio before night audit can close" } ]
      },
      exceptions: {
        "review_due_out" => [ { "guest_name" => "Ben Lee", "confirmation_token" => "WARN-1", "reason" => "Due-out review carried forward" } ]
      })
    sign_in(user)

    get hotel_night_audit_path(hotel, night_audit)

    expect(response.body).to include("Cannot close this date", "Hard Blockers", "Warnings / Review Items")
    expect(response.body).to include("Accounting blocker", "Due-out review carried forward")
  end

  it "renders the compact historical audit packet sections and preserved actions" do
    night_audit = create(:night_audit, hotel: hotel, status: "completed")
    sign_in(user)

    get hotel_night_audit_path(hotel, night_audit)

    expect(response.body).to include("Summary", "Audit Details", "Audit Snapshot", "Payment Status Counts")
    expect(response.body).to include("data-testid=\"night-audit-summary\"")
    expect(response.body).to include("data-testid=\"audit-details-card\"")
    expect(response.body).to include("data-testid=\"audit-snapshot-card\"")
    expect(response.body).to include("data-testid=\"payment-status-counts-card\"")
    expect(response.body).to include("Business-Date Financial Summary", "Manual Adjustments & Voids")
    expect(response.body).to include("View Audit Packet", "Back to Night Audit")
    expect(response.body).to include("Date closed")
    expect(response.body).to include(night_audit.business_date.strftime("%d %b %Y"))
    expect(response.body).to include(hotel_night_audit_path(hotel, night_audit))
  end
end
