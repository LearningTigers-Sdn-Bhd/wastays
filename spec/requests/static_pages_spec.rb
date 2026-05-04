require 'rails_helper'

RSpec.describe "StaticPages", type: :request do
  describe "GET /" do
    it "returns http success" do
      get "/"
      expect(response).to have_http_status(:success)
    end

    it "does not render the mobile bottom nav on the landing page" do
      get "/"

      expect(response.body).not_to include('text-[10px] font-medium">Account</span>')
      expect(response.body).not_to include('text-[10px] font-medium">Search</span>')
    end

    it "links landing page signup CTAs to the registration form" do
      get "/"

      expect(response.body).to include(%(href="#{register_path}"))
      expect(response.body).to include("Get Started")
      expect(response.body).to include("Start with WAStays")
    end

    it "links the footer WhatsApp CTA to the configured number" do
      get "/"

      expect(response.body).to include(%(href="https://wa.me/601162023996"))
    end

    it "opens the footer WhatsApp CTA in a new tab" do
      get "/"

      expect(response.body).to include(%(href="https://wa.me/601162023996"))
      expect(response.body).to include(%(target="_blank"))
      expect(response.body).to include(%(rel="noopener noreferrer"))
    end

    it "renders the AI Concierge and Revenue Engine cards without tinted image overlays" do
      get "/"

      expect(response.body).to include('alt="Concierge"')
      expect(response.body).to include('alt="Revenue"')
      expect(response.body).not_to include('bg-gradient-to-b from-[#1e2e2a]/50 to-[#1e2e2a]')
      expect(response.body).not_to include('bg-gradient-to-b from-[#8b6d2e]/50 to-[#8b6d2e]')
    end
  end

  describe "GET /hotels" do
    it "keeps the mobile bottom nav on other public pages" do
      get "/hotels"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('text-[10px] font-medium">Account</span>')
      expect(response.body).to include('text-[10px] font-medium">Search</span>')
    end

    it "routes shared nav anchor links back to the landing page" do
      get "/hotels"

      expect(response.body).to include(%(href="#{root_path(anchor: "products")}"))
      expect(response.body).to include(%(href="#{root_path(anchor: "whatsapp")}"))
      expect(response.body).to include(%(href="#{root_path(anchor: "testimonials")}"))
      expect(response.body).to include(%(href="#{root_path(anchor: "faq")}"))
    end
  end

  describe "GET /explore" do
    it "renders successfully" do
      get "/explore"

      expect(response).to have_http_status(:success)
    end

    it "renders the search submit button without a shadow" do
      get "/explore"

      expect(response.body).to include('Find Stays')
      expect(response.body).not_to include('shadow-xl shadow-brand-primary/40')
    end

    it "shows at most six featured stays" do
      hotels = Array.new(7) do |index|
        create(:hotel,
               status: "approved",
               name: "Featured Hotel #{index + 1}",
               city: "Kuala Lumpur",
               country: "Malaysia")
      end

      hotels.each do |hotel|
        create(:room_type, hotel: hotel, max_adults: 2)
      end

      availability_service = instance_double(BookingEngine::AvailabilityService)
      allow(BookingEngine::AvailabilityService).to receive(:new).and_return(availability_service)
      allow(availability_service).to receive(:find_available_hotels).and_return(hotels)
      allow(availability_service).to receive(:available_rooms_for_hotel) do |hotel|
        [ hotel.room_types.first ]
      end
      allow(availability_service).to receive(:calculate_total_price).and_return(200)

      get "/explore"

      expect(response.body).to include("Featured Hotel 1")
      expect(response.body).to include("Featured Hotel 6")
      expect(response.body).not_to include("Featured Hotel 7")
    end

    it "links the footer back to the landing page sections" do
      get "/explore"

      expect(response.body).to include(%(>Explore Hotel<))
      expect(response.body).to include(%(href="#{explore_path}"))
      expect(response.body).to include(%(href="#{root_path(anchor: "faq")}"))
    end
  end
end
