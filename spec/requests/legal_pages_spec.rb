require "rails_helper"

RSpec.describe "LegalPages", type: :request do
  describe "GET /privacy-policy" do
    it "renders the privacy policy with company identity and contact details" do
      get "/privacy-policy"

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Privacy Policy")
      expect(response.body).to include("WAStays")
      expect(response.body).to include("Jesselton Pixel Sdn Bhd")
      expect(response.body).to include("hello@wastays.com")
    end

    it "does not render the mobile bottom nav" do
      get "/privacy-policy"

      expect(response.body).not_to include('text-[10px] font-medium">Home</span>')
      expect(response.body).not_to include('text-[10px] font-medium">Search</span>')
      expect(response.body).not_to include('text-[10px] font-medium">Help</span>')
      expect(response.body).not_to include('text-[10px] font-medium">Account</span>')
    end
  end

  describe "GET /terms-and-conditions" do
    it "renders the terms page with the platform name and legal contact details" do
      get "/terms-and-conditions"

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Terms &amp; Conditions").or include("Terms & Conditions")
      expect(response.body).to include("WAStays")
      expect(response.body).to include("Jesselton Pixel Sdn Bhd")
      expect(response.body).to include("hello@wastays.com")
    end

    it "does not render the mobile bottom nav" do
      get "/terms-and-conditions"

      expect(response.body).not_to include('text-[10px] font-medium">Home</span>')
      expect(response.body).not_to include('text-[10px] font-medium">Search</span>')
      expect(response.body).not_to include('text-[10px] font-medium">Help</span>')
      expect(response.body).not_to include('text-[10px] font-medium">Account</span>')
    end
  end
end
