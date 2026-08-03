require "rails_helper"

RSpec.describe "Legacy hotel Night Audit routes", type: :request do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account:, plan:, status: "live") }
  let(:user) { create(:user, account:, role: "hotel_staff") }
  let(:role) { create(:role, account:, slug: "night_auditor", name: "Night Auditor") }
  let!(:permission) do
    Permission.find_or_create_by!(slug: "manage_night_audit") { |record| record.name = "Manage Night Audit" }
  end

  before do
    role.permissions << permission
    create(:user_hotel_access, user:, hotel:, role:)
    create(:plan_feature, plan:, feature: create(:feature, feature_group:, slug: "no_show_auto_handling"), enabled: true)
    post login_path, params: { email: user.email, password: user.password }
  end

  it "permanently redirects the former index to report history" do
    get hotel_night_audits_path(hotel)

    expect(response).to redirect_to(hotel_reports_night_audits_path(hotel))
    expect(response).to have_http_status(:moved_permanently)
  end

  it "preserves format and query parameters when redirecting a historical record" do
    audit = create(:night_audit, hotel:, status: "completed")

    get hotel_night_audit_path(hotel, audit, format: :pdf, tab: "financial-summary")

    expect(response).to redirect_to(hotel_reports_night_audit_path(hotel, audit, format: :pdf, tab: "financial-summary"))
    expect(response).to have_http_status(:moved_permanently)
  end

  it "does not expose preparation-only records through the legacy show route" do
    audit = create(:night_audit, hotel:, status: "preparing")

    get hotel_night_audit_path(hotel, audit)

    expect(response).to have_http_status(:not_found)
  end
end
