require "rails_helper"
require "securerandom"

RSpec.describe "Admin global search", type: :request do
  let(:token) { SecureRandom.hex(6) }
  let(:account) { create(:account, name: "Global Search Admin #{token}") }
  let(:superadmin) { create(:user, :superadmin, account: account, email: "admin-global-search-#{token}@example.com") }

  before do
    sign_in_as(superadmin)
  end

  it "returns admin pages that are not limited to the old sidebar-only set" do
    get admin_global_search_index_path, params: { q: "refund" }, headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    titles = JSON.parse(response.body).fetch("results").map { |row| row.fetch("title") }

    expect(titles).to include("Refund Policy", "Refund Requests")
  end

  it "returns developer and support destinations" do
    get admin_global_search_index_path, params: { q: "developer" }, headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    developer_titles = JSON.parse(response.body).fetch("results").map { |row| row.fetch("title") }
    expect(developer_titles).to include("Developer Guide")

    get admin_global_search_index_path, params: { q: "help" }, headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    help_titles = JSON.parse(response.body).fetch("results").map { |row| row.fetch("title") }
    expect(help_titles).to include("Help & Support")
  end
end
