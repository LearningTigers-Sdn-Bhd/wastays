require "rails_helper"
require "securerandom"

RSpec.describe "Admin::SetupFeeRules", type: :request do
  let(:token) { SecureRandom.hex(6) }
  let(:account) { create(:account, name: "Setup Fee Request #{token}") }
  let(:superadmin) { create(:user, :superadmin, account: account, email: "setup-fee-request-#{token}@example.com") }

  before do
    sign_in_as(superadmin)
  end

  describe "GET /admin/setup_fee_rules" do
    it "renders the setup fee settings page" do
      get admin_setup_fee_rules_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Setup Fee Settings")
      expect(response.body).to include("Setup Fee Amount (MYR)")
    end
  end

  describe "POST /admin/setup_fee_rules" do
    it "creates a global default setup fee rule" do
      expect do
        post admin_setup_fee_rules_path, params: {
          setup_fee_rule: {
            amount: "500.00",
            settable_type: "",
            settable_id: ""
          }
        }
      end.to change(SetupFeeRule, :count).by(1)

      rule = SetupFeeRule.order(:created_at).last

      expect(response).to redirect_to(admin_setup_fee_rules_path)
      expect(rule.amount.to_s).to eq("500.0")
      expect(rule.currency).to eq("MYR")
      expect(rule.status).to eq("active")
      expect(rule.settable).to be_nil
      expect(rule.settable_type).to be_nil
      expect(rule.settable_id).to be_nil
    end

    it "creates a hotel override setup fee rule" do
      hotel = create(:hotel, name: "Override Hotel #{token}")

      expect do
        post admin_setup_fee_rules_path, params: {
          setup_fee_rule: {
            amount: "1200.00",
            settable_type: "Hotel",
            settable_id: hotel.id
          }
        }
      end.to change(SetupFeeRule, :count).by(1)

      rule = SetupFeeRule.order(:created_at).last

      expect(response).to redirect_to(admin_setup_fee_rules_path)
      expect(rule.amount.to_s).to eq("1200.0")
      expect(rule.settable).to eq(hotel)
      expect(rule.status).to eq("active")
    end

    it "rejects a duplicate active global default" do
      create(:setup_fee_rule, :global_default, amount: 500.00)

      expect do
        post admin_setup_fee_rules_path, params: {
          setup_fee_rule: {
            amount: "650.00",
            settable_type: "",
            settable_id: ""
          }
        }
      end.not_to change(SetupFeeRule, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Setup Fee Settings")
      expect(response.body).to include("Only one active global default setup fee is allowed.")
    end
  end

  describe "DELETE /admin/setup_fee_rules/:id" do
    it "deletes a setup fee rule" do
      rule = create(:setup_fee_rule, :global_default, amount: 500.00)

      expect do
        delete admin_setup_fee_rule_path(rule)
      end.to change(SetupFeeRule, :count).by(-1)

      expect(response).to redirect_to(admin_setup_fee_rules_path)
    end
  end
end
