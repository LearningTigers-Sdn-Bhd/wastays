require "rails_helper"

RSpec.describe "Admin::Plans", type: :request do
  let(:account) { create(:account) }
  let(:superadmin) { create(:user, :superadmin, account: account) }
  let!(:plan) { create(:plan, name: "Core", slug: "core") }
  let!(:feature_group) { create(:feature_group, slug: "aic", name: "AI Concierge (AIC)") }
  let!(:external_feature) { create(:feature, feature_group: feature_group, slug: "whatsapp_automation_flows", name: "WhatsApp automation flows") }
  let!(:gated_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page", name: "AI Concierge Page") }
  let!(:be_group) { create(:feature_group, slug: "be", name: "Booking Engine (BE)") }
  let!(:folio_feature) { create(:feature, feature_group: be_group, slug: "folio_management_billing", name: "Folio Management & Billing") }
  let!(:external_plan_feature) { create(:plan_feature, plan: plan, feature: external_feature, enabled: true) }
  let!(:gated_plan_feature) { create(:plan_feature, plan: plan, feature: gated_feature, enabled: true) }
  let!(:folio_plan_feature) { create(:plan_feature, plan: plan, feature: folio_feature, enabled: true) }

  before do
    sign_in_as(superadmin)
  end

  describe "GET /admin/plans" do
    it "shows disclaimer and disables external AIC rows" do
      get admin_plans_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Some AIC rows are managed outside WAStays today")

      document = Nokogiri::HTML(response.body)
      external_row = document.css("tr").find { |row| row.text.include?("WhatsApp automation flows") }
      gated_row = document.css("tr").find { |row| row.text.include?("AI Concierge Page") }

      expect(external_row.css('input[type="checkbox"][disabled]').count).to be >= 1
      expect(gated_row.css('input[type="checkbox"][disabled]').count).to eq(0)
    end

    it "marks folio row as plan default and disables editing" do
      get admin_plans_path

      expect(response).to have_http_status(:ok)

      document = Nokogiri::HTML(response.body)
      folio_row = document.css("tr").find { |row| row.text.include?("Folio Management & Billing") }

      expect(folio_row.text).to include("Plan default")
      expect(folio_row.css('input[type="checkbox"][disabled]').count).to be >= 1
    end
  end

  describe "PATCH /admin/plans/update_matrix" do
    it "ignores updates for disabled external AIC rows" do
      patch update_matrix_admin_plans_path, params: {
        cells: {
          "0" => {
            plan_id: plan.id,
            feature_id: external_feature.id,
            enabled: "0",
            addon: "0",
            level: ""
          },
          "1" => {
            plan_id: plan.id,
            feature_id: gated_feature.id,
            enabled: "0",
            addon: "0",
            level: ""
          }
        }
      }

      expect(response).to redirect_to(admin_plans_path)
      expect(external_plan_feature.reload.enabled).to be(true)
      expect(gated_plan_feature.reload.enabled).to be(false)
    end
  end
end
