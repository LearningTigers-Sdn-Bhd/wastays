# frozen_string_literal: true

require "rails_helper"

# A travel agent arrives on the public homepage signed in. The account menu in
# the corner is the only way back into their own portal from there.
RSpec.describe "The account menu on the public site", type: :request do
  it "gives a corporate user their dashboard, bookings and profile" do
    sign_in_as(create(:user, :corporate))

    get root_path

    page = Capybara.string(response.body)
    expect(page.find("[data-testid='menu-corporate-dashboard']")[:href]).to eq(corporate_dashboard_path)
    expect(page.find("[data-testid='menu-corporate-bookings']")[:href]).to eq(corporate_bookings_path)
    expect(page.find("[data-testid='menu-corporate-profile']")[:href]).to eq(corporate_profile_path)
  end

  it "does not offer those links to anyone else" do
    sign_in_as(create(:user, :superadmin))

    get root_path

    expect(response.body).not_to include("menu-corporate-dashboard")
  end
end
