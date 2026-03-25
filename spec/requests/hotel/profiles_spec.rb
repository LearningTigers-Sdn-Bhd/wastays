require 'rails_helper'

RSpec.describe "Hotel::Profiles", type: :request do
  describe "GET /edit" do
    it "returns http success" do
      get "/hotel/profiles/edit"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /update" do
    it "returns http success" do
      get "/hotel/profiles/update"
      expect(response).to have_http_status(:success)
    end
  end

end
