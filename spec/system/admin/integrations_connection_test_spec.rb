# frozen_string_literal: true

require "rails_helper"

# The request specs post to the endpoint directly, so they cannot catch a fault
# in the request the page builds. This spec drives the real button.
RSpec.describe "Integrations connection test", type: :system, js: true do
  let(:account) { create(:account, name: "Integrations Connection Test") }
  let(:superadmin) { create(:user, :superadmin, account:, email: "integrations-connection-test@example.com") }
  let(:base_url) { "https://api.aroundthat.test/v1" }
  let(:probe_url) { "#{base_url}/places" }

  before do
    driven_by(:cuprite)
    sign_in_through_ui(superadmin)
  end

  it "tests the values on screen without saving them first" do
    request = stub_request(:get, probe_url)
      .with(headers: { "Authorization" => "Bearer typed-key" })
      .to_return(status: 200, body: "{}")

    visit admin_integrations_path(tab: "around_that")

    fill_in "API key", with: "typed-key"
    fill_in "Base URL", with: base_url
    click_button "Test connection"

    expect(page).to have_content("AroundThat answered at api.aroundthat.test")
    expect(request).to have_been_requested
    expect(AppConfig.get("aroundthat_api_key")).to be_nil
  end

  it "reports a rejected key" do
    stub_request(:get, probe_url).to_return(status: 401)

    visit admin_integrations_path(tab: "around_that")

    fill_in "API key", with: "bad-key"
    fill_in "Base URL", with: base_url
    click_button "Test connection"

    expect(page).to have_content("rejected the API key")
  end
end
