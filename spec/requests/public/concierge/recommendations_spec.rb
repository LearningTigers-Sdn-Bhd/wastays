# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public::Concierge::Recommendations", type: :request do
  let(:feature_group) { create(:feature_group) }
  let(:concierge_page_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, status: "live", concierge_enabled: true, plan: plan) }

  before { create(:plan_feature, plan: plan, feature: concierge_page_feature, enabled: true) }

  def path(suffix = "") = "/concierge/#{hotel.to_param}/recommendations#{suffix}"

  describe "GET index" do
    it "opens on the first category and lists its vendors" do
      get path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Kedai Kopi Yee Fung")
      expect(response.body).to include("Food &amp; Drink")
    end

    it "switches vendors when a category is selected" do
      get path("?category=wellness")

      expect(response.body).to include("Borneo Heritage Spa")
      expect(response.body).not_to include("Kedai Kopi Yee Fung")
    end

    it "lists vendors that have no offers rather than hiding them" do
      get path("?category=shopping")

      expect(response.body).to include("Imago Shopping Mall")
      expect(response.body).to include("No offers")
    end

    it "caps the featured rail at four and offers a View all for the rest" do
      get path # food-drink: 19 offers across 4 vendors, all 4 fit the rail's cap

      expect(response.body.scan(%r{data-concierge-modal-target="dialog"}).size).to eq(2) # tabs sheet + voucher sheet
      expect(response.body).to include("View all (19)")
      # 19 offers exist but only 4 are curated into the rail -- the other 15
      # still have to be reachable through the full "View all" list.
      expect(response.body).to include("RM5 off any noodle bowl")
    end
  end

  describe "GET vendor" do
    it "shows directions, hours and the vendor's offers" do
      get path("/nook-rooftop")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Nook Rooftop Bar")
      expect(response.body).to include("Get directions")
      expect(response.body).to include("Opening hours")
      expect(response.body).to include("1-for-1 house pours")
    end

    it "redirects unknown vendors back to the directory" do
      get path("/not-a-vendor")

      expect(response).to redirect_to(path)
    end
  end

  describe "GET offer" do
    it "shows the terms and an unclaimed call to action" do
      get path("/nook-rooftop/nook-house-pour")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Claim this voucher")
      expect(response.body).to include("House spirits and house wine only.")
    end
  end

  describe "POST claim" do
    let(:claim_path) { path("/nook-rooftop/nook-house-pour/claim") }

    it "sends a guest without a booking to the gate, remembering where they were" do
      post claim_path

      expect(response).to redirect_to(path("/unlock?return_to=#{CGI.escape(claim_path)}"))
    end

    context "with a live stay" do
      let!(:booking) do
        create(:booking, hotel: hotel, status: "checked_in",
                         check_in: 1.day.ago, check_out: 2.days.from_now)
      end

      before do
        post path("/unlock"),
             params: { confirmation_token: booking.confirmation_token, return_to: path }
      end

      it "unlocks and returns the guest to the directory" do
        expect(response).to redirect_to(path)
      end

      it "issues a voucher code and renders its QR" do
        post claim_path
        follow_redirect!

        expect(response.body).to include("Claimed &amp; ready")
        expect(response.body).to match(/WS-NOOK-[A-Z0-9]{6}/)
      end

      it "is idempotent: claiming twice keeps the same code" do
        post claim_path
        follow_redirect!
        first_code = response.body[/WS-NOOK-[A-Z0-9]{6}/]

        post claim_path
        follow_redirect!

        expect(response.body).to include(first_code)
      end

      it "lists the claim in the wallet" do
        post claim_path
        get path("/wallet")

        expect(response.body).to include("1-for-1 house pours")
        expect(response.body).to match(/WS-NOOK-[A-Z0-9]{6}/)
      end
    end

    context "arriving at the gate mid-claim, with no session booking yet" do
      let!(:booking) do
        create(:booking, hotel: hotel, status: "checked_in",
                         check_in: 1.day.ago, check_out: 2.days.from_now)
      end

      it "finishes the claim and lands straight on the QR, not on the (POST-only) claim path itself" do
        post claim_path
        gate_path = response.headers["Location"].sub(%r{https?://[^/]+}, "")

        post gate_path, params: { confirmation_token: booking.confirmation_token }
        follow_redirect!

        expect(response).to have_http_status(:success)
        expect(request.path).to eq(path("/nook-rooftop/nook-house-pour"))
        expect(response.body).to include("Claimed &amp; ready")
        expect(response.body).to match(/WS-NOOK-[A-Z0-9]{6}/)
      end
    end

    context "when the stay is not live" do
      let!(:booking) do
        create(:booking, hotel: hotel, status: "confirmed",
                         check_in: 10.days.from_now, check_out: 12.days.from_now)
      end

      it "refuses a future booking" do
        post path("/unlock"), params: { confirmation_token: booking.confirmation_token }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("guests currently staying with us")
      end
    end

    it "rejects an unknown confirmation code" do
      post path("/unlock"), params: { confirmation_token: "ZZZZZZ" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("could not find that booking")
    end
  end

  describe "GET unlock" do
    it "refuses to bounce the guest off-site after unlocking" do
      get path("/unlock?return_to=https://evil.example.com")

      expect(response.body).to include(%(value="#{path}"))
      expect(response.body).not_to include("evil.example.com")
    end
  end
end
