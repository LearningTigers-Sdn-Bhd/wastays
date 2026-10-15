# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Profiles", type: :request do
  let(:superadmin) { create(:user, :superadmin) }

  before { sign_in_as(superadmin) }

  it "renders the shared profile form" do
    get edit_admin_profile_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Change password")
    expect(response.body).to include("Search and select a time zone")
  end
end
