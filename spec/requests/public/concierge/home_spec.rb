require "rails_helper"

RSpec.describe "Public::Concierge::Home", type: :request do
  let(:feature_group) { create(:feature_group) }
  let(:ai_concierge_page_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, status: "live", concierge_enabled: true, plan: plan) }

  before do
    create(:plan_feature, plan: plan, feature: ai_concierge_page_feature, enabled: true)
  end

  describe "GET /concierge/:hotel_code/:public_id" do
    it "returns 200 for a live hotel with concierge enabled" do
      get concierge_home_path(hotel.unique_id, hotel.public_id)
      expect(response).to have_http_status(:ok)
    end

    it "renders the public concierge actions" do
      get concierge_home_path(hotel.unique_id, hotel.public_id)

      expect(response.body).to include("Pre-check in")
      expect(response.body).to include("Book a Room")
      expect(response.body).to include("Recommendations")
      expect(response.body).to include("Property Contacts")
      expect(response.body).to include("Interact with Chatbot")
      expect(response.body).to include('class="guest-tile-grid" data-columns="4"')
    end

    it "keeps the page but drops the chat tile when guest chat is off" do
      hotel.update!(guest_chat_enabled: false)

      get concierge_home_path(hotel.unique_id, hotel.public_id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Property Contacts")
      expect(response.body).not_to include("Interact with Chatbot")
      expect(response.body).not_to include(concierge_chat_path(hotel.unique_id, hotel.public_id))
      # Three tiles: one row on a wide screen.
      expect(response.body).to include('class="guest-tile-grid" data-columns="3"')
    end

    it "returns 404 for a suspended hotel" do
      hotel.update!(status: "suspended")
      get concierge_home_path(hotel.unique_id, hotel.public_id)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when concierge_enabled is false" do
      hotel.update!(concierge_enabled: false)
      get concierge_home_path(hotel.unique_id, hotel.public_id)
      expect(response).to have_http_status(:not_found)
    end

    it "redirects to public hotel page when AI concierge page is excluded from plan" do
      hotel.plan.plan_features.find_by!(feature: ai_concierge_page_feature).update!(enabled: false)

      get concierge_home_path(hotel.unique_id, hotel.public_id)

      expect(response).to redirect_to(hotel_path(hotel.unique_id, hotel.public_id))
      expect(flash[:alert]).to eq("AI concierge is not available for this property.")
    end

    it "returns 404 for an unknown public ID" do
      get concierge_home_path(hotel.unique_id, SecureRandom.uuid)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when the code and public ID do not belong to the same hotel" do
      other = create(:hotel, status: "live")

      get concierge_home_path(other.unique_id, hotel.public_id)

      expect(response).to have_http_status(:not_found)
    end

    # The concierge is reached by scanning a QR code in the room, so a tile that
    # only exists on one of the two home templates is a tile most guests never see.
    it "offers the chat on every device" do
      [
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
      ].each do |user_agent|
        get concierge_home_path(hotel.unique_id, hotel.public_id), headers: { "HTTP_USER_AGENT" => user_agent }

        expect(response.body).to include(concierge_chat_path(hotel.unique_id, hotel.public_id))
        expect(response.body).to include("Interact with Chatbot")
      end
    end

    # One responsive template now serves both, so the tiles a guest is offered
    # no longer depend on how their user agent string is read.
    it "serves the same page to phones and desktops" do
      bodies = [
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
      ].map do |user_agent|
        get concierge_home_path(hotel.unique_id, hotel.public_id), headers: { "HTTP_USER_AGENT" => user_agent }
        response.body
      end

      expect(bodies.first).to eq(bodies.last)
    end

    it "links every tile to its concierge path" do
      get concierge_home_path(hotel.unique_id, hotel.public_id)

      document = response.parsed_body
      public_paths = [
        concierge_check_in_path(hotel.unique_id, hotel.public_id),
        concierge_book_path(hotel.unique_id, hotel.public_id),
        concierge_recommendations_path(hotel.unique_id, hotel.public_id),
        concierge_contact_path(hotel.unique_id, hotel.public_id),
        concierge_chat_path(hotel.unique_id, hotel.public_id)
      ]

      public_paths.each do |path|
        expect(document.at_css("a[href='#{path}']")).to be_present
      end
    end

    it "opens Book a Room in a new tab" do
      get concierge_home_path(hotel.unique_id, hotel.public_id)

      document = response.parsed_body
      book = document.at_css("a[href='#{concierge_book_path(hotel.unique_id, hotel.public_id)}']")
      recommendations = document.at_css("a[href='#{concierge_recommendations_path(hotel.unique_id, hotel.public_id)}']")

      expect(book["target"]).to eq("_blank")
      expect(book["rel"]).to eq("noopener")
      expect(recommendations["target"]).to be_nil
    end

    it "uses the shared Concierge colors for public service cards" do
      get concierge_home_path(hotel.unique_id, hotel.public_id)

      document = response.parsed_body
      tones = {
        concierge_book_path(hotel.unique_id, hotel.public_id) => "booking",
        concierge_recommendations_path(hotel.unique_id, hotel.public_id) => "discovery",
        concierge_contact_path(hotel.unique_id, hotel.public_id) => "contact",
        concierge_chat_path(hotel.unique_id, hotel.public_id) => "conversation"
      }

      tones.each do |path, tone|
        card = document.at_css("a[href='#{path}']")

        expect(card["class"]).to include("guest-service-surface")
        expect(card["data-tone"]).to eq(tone)
        expect(card.at_css(".guest-service-surface__icon")).to be_present
      end

      expect(document.at_css("a[href='#{concierge_check_in_path(hotel.unique_id, hotel.public_id)}']")["class"])
        .not_to include("guest-service-surface")
    end

    it "has no public check-out or request routes" do
      base = concierge_home_path(hotel.unique_id, hotel.public_id)

      [ [ "check-out", :get ], [ "check-out", :post ], [ "requests/new", :get ], [ "requests", :post ] ].each do |suffix, method|
        expect { Rails.application.routes.recognize_path(File.join(base, suffix), method: method) }
          .to raise_error(ActionController::RoutingError)
      end
    end

    it "keeps every action card flat and touch-sized" do
      get concierge_home_path(hotel.unique_id, hotel.public_id)

      document = response.parsed_body
      check_in = document.at_css("a[href='#{concierge_check_in_path(hotel.unique_id, hotel.public_id)}']")
      service_paths = [
        concierge_book_path(hotel.unique_id, hotel.public_id),
        concierge_recommendations_path(hotel.unique_id, hotel.public_id),
        concierge_contact_path(hotel.unique_id, hotel.public_id),
        concierge_chat_path(hotel.unique_id, hotel.public_id)
      ]

      expect(check_in["class"]).to include("touch-manipulation", "rounded-xl")

      # The services share GuestUI::ActionCard with the stay page, so both
      # pages draw one tile.
      service_paths.each do |path|
        expect(document.at_css("a.guest-action-card[href='#{path}']")).to be_present
      end

      [ check_in, *service_paths.map { |path| document.at_css("a[href='#{path}']") } ].each do |card|
        expect(card["class"]).not_to match(/shadow|rounded-\[2rem\]|active:scale/)
        expect(card.element_children.any? { |child| child.name == "svg" }).to be(true)
      end
    end

    it "leads with the hotel's own photograph rather than a stock background" do
      get concierge_home_path(hotel.unique_id, hotel.public_id)

      expect(response.body).to include("landing/bg-1")
    end

    it "uses the concierge typography roles" do
      get concierge_home_path(hotel.unique_id, hotel.public_id)

      document = response.parsed_body
      font_stylesheet = document.css("link[rel='stylesheet']").find do |link|
        link["href"]&.include?("fonts.googleapis.com")
      end

      expect(document.at_css("body")["class"]).to include("font-guest-interface")
      expect(document.at_css("h1")["class"]).to include("font-guest-display")
      expect(font_stylesheet["href"]).to include("family=Lato", "family=Playfair+Display")
    end
  end

  describe "GET /concierge/:hotel_code/:public_id/book" do
    it "redirects to the public hotel page" do
      get concierge_book_path(hotel.unique_id, hotel.public_id)
      expect(response).to redirect_to(hotel_path(hotel.unique_id, hotel.public_id))
    end
  end
end
