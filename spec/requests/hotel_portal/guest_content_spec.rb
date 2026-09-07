require "rails_helper"

RSpec.describe "HotelPortal::GuestContent", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "live") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "shows the six content tabs in order without the gated AI tab" do
    get hotel_guest_content_path(hotel)

    expect(response).to have_http_status(:ok)
    tabs = Nokogiri::HTML(response.body).css("[data-testid='settings-tabs'] a").map { |link| link.text.squish }
    expect(tabs).to eq([ "Overview", "Hotel Info", "Policies", "FAQs", "Amenities", "Wi-Fi" ])
    expect(response.body).to include("tabs-list tabs-list--line")
    expect(Nokogiri::HTML(response.body).css("[data-testid='settings-tabs'] [data-slot='tabs-list']").size).to eq(1)
  end

  it "creates a hotel-scoped Wi-Fi network without rendering its saved password" do
    post hotel_wifi_networks_path(hotel), params: {
      hotel_wifi_network: {
        label: "Guests", ssid: "HotelGuests", password: "private-password",
        security_type: "protected", access_scope: "checked_in_guests", active: "1", position: "0"
      }
    }

    network = hotel.hotel_wifi_networks.find_by!(ssid: "HotelGuests")
    expect(response).to redirect_to(hotel_wifi_networks_path(hotel))

    get edit_hotel_wifi_network_path(hotel, network)
    expect(response.body).not_to include("private-password")
  end

  it "rejects a Wi-Fi network from another hotel" do
    other_hotel = create(:hotel)
    network = create(:hotel_wifi_network, hotel: other_hotel)

    get edit_hotel_wifi_network_path(hotel, network)

    expect(response).to have_http_status(:not_found)
  end

  it "renders one page frame on every Guest Content page" do
    document = create(:hotel_knowledge_document, hotel: hotel, category: "policy")

    {
      hotel_guest_content_path(hotel) => "Overview",
      hotel_knowledge_general_infos_path(hotel) => "Hotel Info",
      hotel_knowledge_policies_path(hotel) => "Policies",
      new_hotel_knowledge_policy_path(hotel) => "Policies",
      hotel_knowledge_policy_path(hotel, document) => "Policies",
      edit_hotel_knowledge_policy_path(hotel, document) => "Policies",
      hotel_knowledge_faqs_path(hotel) => "FAQs",
      hotel_guest_amenities_path(hotel) => "Amenities",
      hotel_wifi_networks_path(hotel) => "Wi-Fi",
      new_hotel_wifi_network_path(hotel) => "Wi-Fi"
    }.each do |path, active_label|
      get path

      body = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok), "#{path} did not render"
      # One static page header on every page. Pages open with a section heading.
      headers = body.css(".panel-page-header")
      expect(headers.size).to eq(1), "#{path} rendered the wrong number of page headers"
      expect(headers.first.text.squish).to start_with("Guest Content Settings"), "#{path} lost the static header"
      expect(body.css("[data-testid='settings-tabs'] [data-slot='tabs-list']").size).to eq(1), "#{path} rendered more than one tabs list"

      active = body.css("[data-testid='settings-tabs'] [data-slot='tabs-trigger'][aria-current='page']")
      expect(active.map { |tab| tab["data-tab-label"] }).to eq([ active_label ]), "#{path} marked the wrong tab"
    end
  end

  it "keeps a validation error on the Wi-Fi page inside the same frame" do
    post hotel_wifi_networks_path(hotel), params: {
      hotel_wifi_network: { label: "", ssid: "", security_type: "protected", access_scope: "checked_in_guests" }
    }

    body = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:unprocessable_content)
    expect(body.css(".panel-page-header").size).to eq(1)
    active = body.css("[data-testid='settings-tabs'] [data-slot='tabs-trigger'][aria-current='page']")
    expect(active.map { |tab| tab["data-tab-label"] }).to eq([ "Wi-Fi" ])
  end

  it "stacks every page body section in the shared rhythm" do
    document = create(:hotel_knowledge_document, hotel: hotel, category: "policy")

    [
      hotel_guest_content_path(hotel),
      hotel_knowledge_general_infos_path(hotel),
      hotel_knowledge_policies_path(hotel),
      new_hotel_knowledge_policy_path(hotel),
      hotel_knowledge_policy_path(hotel, document),
      hotel_guest_amenities_path(hotel),
      hotel_wifi_networks_path(hotel),
      new_hotel_wifi_network_path(hotel)
    ].each do |path|
      get path

      body = Nokogiri::HTML(response.body).at_css("[data-testid='guest-content-body']")
      expect(body).to be_present, "#{path} did not use the Guest Content layout"
      expect(body["class"]).to eq("space-y-4"), "#{path} changed the body rhythm"
    end
  end

  # A page that wraps its own sections in one element gets no gaps between them,
  # because the layout only spaces its direct children.
  it "renders the overview sections as direct children of the body stack" do
    get hotel_guest_content_path(hotel)

    body = Nokogiri::HTML(response.body).at_css("[data-testid='guest-content-body']")
    page_sections = body.element_children.reject { |node| node["class"].to_s.include?("panel-page-header") || node["data-testid"] == "settings-tabs" }
    expect(page_sections.map(&:name)).to eq(%w[section section])
  end

  # A Button built with a block loses its text inside a capture, which renders
  # an empty square. Every section action must carry a label.
  it "labels every section action" do
    document = create(:hotel_knowledge_document, hotel: hotel, category: "policy")

    {
      hotel_knowledge_policies_path(hotel) => [ "Add Policy" ],
      hotel_knowledge_faqs_path(hotel) => [ "Add FAQ" ],
      hotel_guest_amenities_path(hotel) => [ "Manage amenities" ],
      hotel_wifi_networks_path(hotel) => [ "Add network" ],
      new_hotel_knowledge_policy_path(hotel) => [ "Back" ],
      edit_hotel_knowledge_policy_path(hotel, document) => [ "Back" ],
      hotel_knowledge_policy_path(hotel, document) => [ "Back", "Edit" ]
    }.each do |path, labels|
      get path

      body = Nokogiri::HTML(response.body).at_css("[data-testid='guest-content-body']")
      first_section = body.css("> div").find { |node| node.at_css("h2") && !node["class"].to_s.include?("panel-page-header") }
      expect(first_section.css(".panel-button").map { |button| button.text.squish }).to eq(labels), "#{path} section actions are wrong"
    end
  end

  it "puts the Hotel Info actions on the card and the section, not in a page header" do
    get hotel_knowledge_general_infos_path(hotel)

    body = Nokogiri::HTML(response.body).at_css("[data-testid='guest-content-body']")
    expect(body.css(".panel-page-header .panel-button")).to be_empty

    summary = body.at_css("[aria-labelledby='property-summary-heading']")
    expect(summary.css(".panel-button").map { |button| button.text.squish }).to eq([ "Property Settings" ])

    additional = body.at_css("[aria-label='Additional Information']")
    expect(additional.css("h2").first.text.squish).to eq("Additional Information")
    section_header = additional.element_children.first
    expect(section_header.css(".panel-button").map { |button| button.text.squish }).to eq([ "Add Information" ])
  end
end
