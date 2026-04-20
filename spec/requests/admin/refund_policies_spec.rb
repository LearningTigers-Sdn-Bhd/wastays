require "rails_helper"

RSpec.describe "Admin::RefundPolicies", type: :request do
  let(:superadmin) { create(:user, :superadmin) }

  before { sign_in_as(superadmin) }

  describe "GET /admin/refund_policy" do
    it "returns http success" do
      get admin_refund_policy_path
      expect(response).to have_http_status(:success)
    end

    it "is inaccessible to non-superadmin" do
      delete logout_path
      get admin_refund_policy_path
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "PATCH /admin/refund_policy" do
    it "creates and updates the policy" do
      patch admin_refund_policy_path, params: {
        refund_policy: { min_days_before_checkin: 5, refund_percentage: 75.0 }
      }
      policy = RefundPolicy.first
      expect(policy.min_days_before_checkin).to eq(5)
      expect(policy.refund_percentage).to eq(75.0)
      expect(response).to redirect_to(admin_refund_policy_path)
    end

    it "re-renders with errors on invalid data" do
      patch admin_refund_policy_path, params: {
        refund_policy: { min_days_before_checkin: -1, refund_percentage: 150.0 }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /admin/refund_policy" do
    it "clears existing policy" do
      create(:refund_policy, min_days_before_checkin: 3, refund_percentage: 85.0)

      expect {
        delete admin_refund_policy_path
      }.to change(RefundPolicy, :count).by(-1)

      expect(response).to redirect_to(admin_refund_policy_path)
    end

    it "redirects even when policy does not exist" do
      delete admin_refund_policy_path
      expect(response).to redirect_to(admin_refund_policy_path)
    end
  end
end
