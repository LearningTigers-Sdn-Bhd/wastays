# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public::Concierge::Info", type: :request do
  let(:feature_group) { create(:feature_group) }
  let(:ai_concierge_page_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, status: "live", concierge_enabled: true, plan: plan) }
  let(:home_path) { concierge_home_path(hotel.unique_id, hotel.public_id) }
  let(:info_path) { concierge_info_path(hotel.unique_id, hotel.public_id) }

  def section_path(section) = concierge_info_section_path(hotel.unique_id, hotel.public_id, section)

  before do
    create(:plan_feature, plan: plan, feature: ai_concierge_page_feature, enabled: true)
  end

  context "when the property filled Guest Content" do
    before do
      swimming_pool = create(:amenity, :hotel, name: "Swimming Pool")
      # Hotel caches the allowed slugs for the process, so a new amenity is
      # written straight to the column.
      hotel.update_column(:amenities, [ swimming_pool.slug ])
      create(:hotel_amenity_detail, hotel: hotel, amenity: swimming_pool, location: "Level 5")
      create(:property_policy, hotel: hotel, check_in_time: "15:00")
      create(:hotel_guest_instruction, hotel: hotel)
      create(:hotel_transport_detail, :with_parking, hotel: hotel)
      create(:hotel_knowledge_document, hotel: hotel, category: "policy", title: "House Rules",
             content: "No parties after 10 PM.", metadata: { "policy_key" => "house_rules" })
      create(:hotel_knowledge_document, hotel: hotel, category: "faq", title: "Common questions",
             content: "Q: Is breakfast included?\nA: Yes, from 7 AM.",
             metadata: { "qa_pairs" => [ { "question" => "Is breakfast included?", "answer" => "Yes, from 7 AM." } ] })
      create(:hotel_wifi_network, hotel: hotel, access_scope: "confirmed_guests", ssid: "LobbyGuest")
    end

    it "shows the Property Guide tiles on the home page, with counts" do
      get home_path

      expect(response.body).to include("Property Guide", info_path, section_path("amenities"),
                                       section_path("policies"), section_path("faqs"),
                                       "1 available", "1 policy", "1 question")
      guide = Nokogiri::HTML(response.body).at_css("#property-guide-title + .guest-tile-grid")
      expect(guide["data-columns"]).to eq("4")
      # One calm colour for the reading pages, apart from the service tiles.
      expect(guide.css("a.guest-action-card").map { |tile| tile["data-tone"] }.uniq).to eq([ "guide" ])
      expect(response.body).not_to include("LobbyGuest")
    end

    it "shows arrival, getting around and the property on the Property Info page" do
      get info_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Arrival and departure", "15:00",
                                       "Please present your booking confirmation at reception.",
                                       "Getting around", "Take exit 14 from the coastal highway.", "Valet")
      expect(response.body).not_to include("Swimming Pool", "No parties after 10 PM.", "Is breakfast included?")

      page = Nokogiri::HTML(response.body)
      expect(page.css("h2.guest-section-title").map(&:text)).to eq([ "Arrival and departure", "Getting around" ])
      expect(page.css(".guest-guide-card__subtitle").map(&:text)).to include("Check-in from 15:00")
      expect(page.at_css("#getting-around-title + .guest-card-grid")["data-columns"]).to eq("3")
      expect(page.at_css(".guest-guide-card__action a[href*='google.com/maps']").text).to include("Open in Maps")
    end

    it "shows each other section on its own page" do
      get section_path("amenities")
      expect(response.body).to include("Swimming Pool", "Level 5")

      get section_path("policies")
      expect(response.body).to include("House Rules", "No parties after 10 PM.")
      page = Nokogiri::HTML(response.body)
      expect(page.at_css(".guest-aside-layout")["data-aside"]).to eq("true")
      expect(page.at_css(".guest-aside-layout__aside").text).to include("At a glance", "Check-in from", "15:00")

      get section_path("faqs")
      expect(response.body).to include("Is breakfast included?", "Yes, from 7 AM.")
    end
  end

  describe "the FAQs page" do
    def faq_document(title, count)
      pairs = Array.new(count) { |index| { "question" => "#{title} question #{index + 1}?", "answer" => "Answer #{index + 1}." } }
      create(:hotel_knowledge_document, hotel: hotel, category: "faq", title: title,
             content: pairs.map { |pair| "Q: #{pair['question']}\nA: #{pair['answer']}" }.join("\n\n"),
             metadata: { "qa_pairs" => pairs })
    end

    it "keeps a short list plain, with one card and no search" do
      faq_document("Common questions", 3)

      get section_path("faqs")

      page = Nokogiri::HTML(response.body)
      expect(page.css("details.guest-disclosure").size).to eq(3)
      expect(page.at_css("#faq-search")).to be_nil
      expect(page.css(".guest-card__title").map(&:text)).to eq([ "Still have a question?" ])
    end

    it "names each group and offers a search once the list is long" do
      faq_document("Dining", 3)
      faq_document("Getting here", 3)

      get section_path("faqs")

      page = Nokogiri::HTML(response.body)
      expect(page.css(".guest-card__title").map(&:text)).to include("Dining", "Getting here")
      expect(page.at_css("[data-controller='admin-sidebar-search'] #faq-search")).to be_present
      expect(page.at_css("details[data-search-text='Dining question 1? Answer 1.']")).to be_present
    end

    it "sends a guest with an open question to the contact page" do
      faq_document("Common questions", 1)

      get section_path("faqs")

      expect(response.body).to include("Still have a question?", concierge_contact_path(hotel.unique_id, hotel.public_id))
    end
  end

  it "shows no Property Guide on the home page when the property added nothing" do
    get home_path

    expect(response.body).not_to include("Property Guide")
  end

  it "says so on a page the property has not filled" do
    get section_path("faqs")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("The property has not added this information yet.")
  end

  it "opens with the description, and keeps the extra topics in their own section" do
    hotel.update!(description: "A beach resort on Pantai Cenang.")
    create(:property_policy, hotel: hotel)
    create(:hotel_knowledge_document, hotel: hotel, category: "general_info", title: "Dining", content: "Breakfast from 7 AM.")

    get info_path

    page = Nokogiri::HTML(response.body)
    expect(page.css("h2.guest-section-title").map(&:text)).to eq([ "About the property", "Arrival and departure", "Additional information" ])
    expect(page.at_css("section[aria-labelledby='about-title']").text).to include("A beach resort on Pantai Cenang.")
    expect(page.at_css("section[aria-labelledby='additional-info-title'] .guest-guide-card h3").text).to eq("Dining")
  end

  it "hides every PDF" do
    create(:hotel_knowledge_document, hotel: hotel, category: "general_info", title: "Brochure", source_type: "pdf",
           content: "Extracted text")

    get info_path

    expect(response.body).not_to include("Brochure")
  end

  it "has no public Wi-Fi page" do
    get "/concierge/#{hotel.unique_id}/#{hotel.public_id}/info/wifi"

    expect(response).to have_http_status(:not_found)
  end
end
