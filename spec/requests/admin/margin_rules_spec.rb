require 'rails_helper'
require 'securerandom'

RSpec.describe "Admin::MarginRules", type: :request do
  let(:token) { SecureRandom.hex(6) }
  let(:account) { create(:account, name: "Margin Request #{token}") }
  let(:superadmin) { create(:user, :superadmin, account: account, email: "margin-request-#{token}@example.com") }
  let!(:global_rule) { create(:margin_rule, rate: 12.0, settable: nil, status: "active") }

  before do
    sign_in_as(superadmin)
  end

  describe "GET /index" do
    it "renders the redesigned margin settings page" do
      get "/admin/margin_rules"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('class="text-2xl font-bold tracking-tight text-slate-950 sm:text-3xl">Margin Settings')
      expect(response.body).to include("Margin Settings")
      expect(response.body).to include("Set the commission rules WAStays applies across the platform, hotels, and room types.")
      expect(response.body).to include('class="text-lg font-bold tracking-tight text-slate-950 sm:text-xl">Add New Rule')
      expect(response.body).to include('class="text-lg font-bold tracking-tight text-slate-950 sm:text-xl">Rule Registry')
      expect(response.body).to include("Total Rules")
      expect(response.body).to include("Active Rules")
      expect(response.body).to include("Global Defaults")
      expect(response.body).to include("Overrides")
      expect(response.body).to include("Rule Registry")
      expect(response.body).to include("Create and manage commission rules for default coverage or targeted overrides.")
      expect(response.body).to include("Global Default")
      expect(response.body).to include("Applied when no hotel or room override exists")
      expect(response.body).to include("12.0%")
      expect(response.body).to include("Add New Rule")
    end
  end
end
