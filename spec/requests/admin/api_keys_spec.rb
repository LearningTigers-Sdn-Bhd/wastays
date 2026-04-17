require "rails_helper"
require "securerandom"

RSpec.describe "Admin::ApiKeys", type: :request do
  let(:token) { SecureRandom.hex(6) }
  let(:admin_account) { create(:account, name: "Admin API #{token}") }
  let(:superadmin) { create(:user, :superadmin, account: admin_account, email: "admin-api-#{token}@example.com") }

  before do
    sign_in_as(superadmin)
  end

  describe "POST /admin/api_keys" do
    let(:params) do
      {
        api_key: {
          name: "Primary Integration Key",
          bearer_type: "",
          bearer_id: ""
        }
      }
    end

    it "reveals the generated token in a one-time modal on index" do
      post admin_api_keys_path, params: params

      expect(response).to redirect_to(admin_api_keys_path)
      follow_redirect!

      generated_key = ApiKey.order(:created_at).last
      expect(response.body).to include("API Key Created")
      expect(response.body).to include("This API key is shown only once")
      expect(response.body).to include(generated_key.token)
      expect(response.body).not_to include("API Key created:")
    end

    it "does not show the reveal modal again after the first page load" do
      post admin_api_keys_path, params: params
      follow_redirect!

      get admin_api_keys_path

      expect(response.body).not_to include("API Key Created")
      expect(response.body).not_to include("This API key is shown only once")
    end
  end
end
