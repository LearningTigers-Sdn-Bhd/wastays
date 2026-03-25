require 'rails_helper'

RSpec.describe "Public::Registrations", type: :request do
  describe "GET /new" do
    it "returns http success" do
      get "/public/registrations/new"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /create" do
    it "returns http success" do
      get "/public/registrations/create"
      expect(response).to have_http_status(:success)
    end
  end

end
