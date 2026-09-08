require "rails_helper"

RSpec.describe "HotelPortal::GuestContent", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "live") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }
  let(:sheet_headers) { { "Turbo-Frame" => "settings_action_sheet" } }
  let(:sheet_submit_headers) { sheet_headers.merge("Accept" => Mime[:turbo_stream].to_s) }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "shows the seven content tabs in order without the gated AI tab" do
    get hotel_guest_content_path(hotel)

    expect(response).to have_http_status(:ok)
    tabs = Nokogiri::HTML(response.body).css("[data-testid='settings-tabs'] a").map { |link| link.text.squish }
    expect(tabs).to eq([ "Overview", "Hotel Info", "Policies", "FAQs", "Amenities", "Wi-Fi", "Contact & Escalation" ])
    expect(response.body).to include("tabs-list tabs-list--line")
    expect(Nokogiri::HTML(response.body).css("[data-testid='settings-tabs'] [data-slot='tabs-list']").size).to eq(1)
  end

  it "shows the Hotel Information heading and three subtabs" do
    get hotel_knowledge_general_infos_path(hotel)

    document = response.parsed_body
    expect(response).to have_http_status(:ok)
    expect(document.at_css("[data-testid='guest-content-body'] > div h2").text.squish).to eq("Hotel Information")
    expect(document.text.squish).to include("Manage the property summary, stay instructions, and additional information shared with guests.")

    subtabs = document.at_css("[data-testid='guest-content-subtabs']")
    expect(subtabs.css("[data-slot='tabs-trigger']").map { |tab| tab["data-tab-label"] })
      .to eq([ "Property Summary", "Arrival & Departure", "Additional Information" ])
    expect(subtabs.at_css("[data-tab-label='Property Summary'][aria-current='page']")).to be_present
  end

  it "keeps property contact and location on Property Summary only" do
    hotel.update!(description: "A quiet harbour hotel", contact_email: "private-property@example.test", city: "Semporna")
    create(:property_policy, hotel: hotel, check_in_time: "15:00", check_out_time: "11:00")

    get hotel_knowledge_general_infos_path(hotel)
    expect(response.body).to include("private-property@example.test", "Semporna")

    get hotel_guest_arrival_departure_path(hotel)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("private-property@example.test", hotel.address)
    expect(response.body).to include("3:00 PM", "11:00 AM")

    document = response.parsed_body
    expect(document.at_css("[data-testid='settings-tabs'] [data-tab-label='Hotel Info'][aria-current='page']")).to be_present
    expect(document.at_css("[data-testid='guest-content-subtabs'] [data-tab-label='Arrival & Departure'][aria-current='page']")).to be_present
    expect(document.at_css("a[href='#{hotel_general_settings_path(hotel)}']")).to be_present
  end

  it "renders three flat columns and gives each instruction its own dirty-state form" do
    get hotel_guest_arrival_departure_path(hotel)

    document = response.parsed_body
    layout = document.at_css("[data-testid='arrival-departure-layout']")
    expect(layout["class"]).to include("grid-cols-1", "lg:grid-cols-3")
    expect(layout.css("h2").map { |heading| heading.text.squish }).to eq(
      [ "Standard Check-in & Check-out Time", "Arrival Instructions", "Departure Instructions" ]
    )
    expect(layout.text.squish).to include(
      "These times come from General Settings, which remains the source of truth.",
      "Tell guests what to do when they arrive at the property.",
      "Tell guests what to do before they leave the property."
    )
    expect(layout.css(".rounded-md, .bg-card, .shadow-sm")).to be_empty

    forms = layout.css("form[action='#{hotel_guest_arrival_departure_path(hotel)}']")
    expect(forms.map { |form| form.at_css("input[name='section']")[:value] })
      .to eq(%w[arrival-instructions departure-instructions])
    forms.each do |form|
      expect(form["class"]).to include("lg:w-[85%]")
      expect(form["data-controller"]).to eq("form-dirty")
      expect(form.css("textarea").count).to eq(1)
      expect(form.at_css("button[type='submit'][data-form-dirty-target='submit']")[:disabled]).to be_present
      expect(form.at_css("button[type='reset'][data-form-dirty-target='cancel']")[:hidden]).to be_present
    end
    standard_times = layout.at_css("#standard-times")
    expect(standard_times["class"]).to include("lg:w-[85%]")
    expect(standard_times.at_css("form")).to be_nil
    expect(standard_times.at_css("footer.flex.justify-end a")["href"]).to eq(hotel_general_settings_path(hotel))
  end

  it "saves each instruction independently in one hotel-scoped record" do
    instruction = create(
      :hotel_guest_instruction,
      hotel: hotel,
      arrival_instructions: "Use the lobby entrance.",
      departure_instructions: "Leave keys at reception."
    )

    expect {
      patch hotel_guest_arrival_departure_path(hotel), params: {
        section: "arrival-instructions",
        hotel_guest_instruction: { arrival_instructions: "Use the side entrance." }
      }
    }.not_to change(HotelGuestInstruction, :count)

    expect(response).to redirect_to(hotel_guest_arrival_departure_path(hotel))
    expect(instruction.reload.arrival_instructions).to eq("Use the side entrance.")
    expect(instruction.departure_instructions).to eq("Leave keys at reception.")

    patch hotel_guest_arrival_departure_path(hotel), params: {
      section: "departure-instructions",
      hotel_guest_instruction: { departure_instructions: "Leave keys in the box." }
    }

    expect(instruction.reload.arrival_instructions).to eq("Use the side entrance.")
    expect(instruction.departure_instructions).to eq("Leave keys in the box.")
  end

  it "creates the hotel-scoped instruction record from one section" do
    expect {
      patch hotel_guest_arrival_departure_path(hotel), params: {
        section: "arrival-instructions",
        hotel_guest_instruction: { arrival_instructions: "Use the lobby entrance." }
      }
    }.to change(HotelGuestInstruction, :count).by(1)

    expect(hotel.reload.guest_instruction.arrival_instructions).to eq("Use the lobby entrance.")
    expect(hotel.guest_instruction.departure_instructions).to be_nil
  end

  it "cannot update another hotel's guest instructions" do
    other_hotel = create(:hotel)
    other_instruction = create(:hotel_guest_instruction, hotel: other_hotel)

    patch hotel_guest_arrival_departure_path(hotel), params: {
      hotel_guest_instruction: {
        arrival_instructions: "Instructions for this hotel.",
        departure_instructions: "Departure for this hotel."
      }
    }

    expect(hotel.reload.guest_instruction.arrival_instructions).to eq("Instructions for this hotel.")
    expect(other_instruction.reload.arrival_instructions).not_to eq("Instructions for this hotel.")
  end

  it "requires both stay instructions for Hotel Info readiness" do
    hotel.update!(description: "A complete property summary", contact_email: "hotel@example.test")

    get hotel_guest_content_path(hotel)
    expect(response.body).to include("Add arrival instructions and departure instructions.")

    instruction = create(:hotel_guest_instruction, hotel: hotel, arrival_instructions: "Check in at reception.", departure_instructions: "")
    get hotel_guest_content_path(hotel)
    expect(response.body).to include("Add departure instructions.")

    instruction.update!(departure_instructions: "Return the key at reception.")
    get hotel_guest_content_path(hotel)
    hotel_info_row = response.parsed_body.css("[aria-label='Content readiness'] h3").find { |heading| heading.text.squish == "Hotel Info" }.parent.parent
    expect(hotel_info_row.text.squish).to include("Hotel Info Ready Property summary and stay instructions are ready.")
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

  it "renders the Wi-Fi registry as a table with quick controls" do
    primary = create(:hotel_wifi_network, hotel: hotel, label: "Lobby", primary_network: true)
    secondary = create(:hotel_wifi_network, hotel: hotel, label: "Pool", active: false)

    get hotel_wifi_networks_path(hotel)

    document = Nokogiri::HTML(response.body)
    table = document.at_css("table[data-testid='wifi-networks-table']")
    expect(table.css("thead th").map { |heading| heading.text.squish }).to eq([ "Active", "Network", "Security", "Guest access", "Action" ])
    expect(table.css("tbody tr").size).to eq(2)
    expect(table.at_css("#wifi-network-row-#{primary.id} input[role='switch'][disabled]")).to be_present
    expect(table.at_css("#wifi-network-row-#{secondary.id} input[role='switch']:not([disabled])")).to be_present
    expect(table.css("select[name='hotel_wifi_network[security_type]']").size).to eq(2)
    expect(table.css("select[name='hotel_wifi_network[access_scope]']").size).to eq(2)
    expect(table.css("a[data-turbo-frame='settings_action_sheet']").map { |link| link.text.squish }).to eq([ "Manage", "Manage" ])
  end

  it "keeps the Wi-Fi table visible in the empty state" do
    get hotel_wifi_networks_path(hotel)

    table = response.parsed_body.at_css("table[data-testid='wifi-networks-table']")
    expect(table).to be_present
    expect(table.css("thead th").map { |heading| heading.text.squish }).to eq([ "Active", "Network", "Security", "Guest access", "Action" ])

    empty_row = table.at_css("tbody tr td[colspan='5'] .panel-empty-state")
    expect(empty_row.text.squish).to include("No guest Wi-Fi networks", "Add network")
    expect(empty_row.at_css("a[data-turbo-frame='settings_action_sheet']")).to be_present
  end

  it "renders new and edit Wi-Fi forms in the settings sheet" do
    network = create(:hotel_wifi_network, hotel: hotel)

    get new_hotel_wifi_network_path(hotel), headers: sheet_headers
    new_sheet = response.parsed_body.at_css("turbo-frame#settings_action_sheet dialog#add-wifi-network-sheet")
    expect(new_sheet).to be_present
    password_attributes = new_sheet.at_css("input[type='password']").attribute_nodes.to_h { |attribute| [ attribute.name, attribute.value ] }
    expect(password_attributes).to include(
      "autocomplete" => "one-time-code",
      "data-1p-ignore" => "true",
      "data-lpignore" => "true",
      "data-bwignore" => "true",
      "data-protonpass-ignore" => "true"
    )
    expect(new_sheet.at_css("input[name='hotel_wifi_network[primary_network]'][role='switch']")).to be_present

    get edit_hotel_wifi_network_path(hotel, network), headers: sheet_headers
    sheet = response.parsed_body.at_css("turbo-frame#settings_action_sheet dialog#edit-wifi-network-sheet")
    expect(sheet).to be_present
    expect(sheet.text).not_to include("guest-secret")
  end

  it "completes the Wi-Fi sheet after a valid update" do
    network = create(:hotel_wifi_network, hotel: hotel)

    patch hotel_wifi_network_path(hotel, network), params: {
      hotel_wifi_network: { label: "Updated network" }
    }, headers: sheet_submit_headers

    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include('action="complete_sheet"', 'target="settings_action_sheet"')
    expect(network.reload.label).to eq("Updated network")
  end

  it "quick updates the security, guest access, and active values" do
    create(:hotel_wifi_network, hotel: hotel, primary_network: true)
    network = create(:hotel_wifi_network, hotel: hotel, primary_network: false)

    patch quick_update_hotel_wifi_network_path(hotel, network), params: { hotel_wifi_network: { security_type: "open" } }
    expect(network.reload).to be_security_type_open

    patch quick_update_hotel_wifi_network_path(hotel, network), params: { hotel_wifi_network: { access_scope: "confirmed_guests" } }
    expect(network.reload).to be_access_scope_confirmed_guests

    patch quick_update_hotel_wifi_network_path(hotel, network), params: { hotel_wifi_network: { active: "0" } }
    expect(network.reload).not_to be_active
  end

  it "does not deactivate the primary Wi-Fi network through a quick update" do
    network = create(:hotel_wifi_network, hotel: hotel, primary_network: true, active: true)

    patch quick_update_hotel_wifi_network_path(hotel, network), params: { hotel_wifi_network: { active: "0" } }

    expect(response).to redirect_to(hotel_wifi_networks_path(hotel))
    expect(flash[:alert]).to eq("The primary Wi-Fi network must stay active.")
    expect(network.reload).to be_active
  end

  it "renders one page frame on every Guest Content page" do
    {
      hotel_guest_content_path(hotel) => "Overview",
      hotel_knowledge_general_infos_path(hotel) => "Hotel Info",
      hotel_guest_arrival_departure_path(hotel) => "Hotel Info",
      hotel_knowledge_additional_information_path(hotel) => "Hotel Info",
      hotel_knowledge_policies_path(hotel) => "Policies",
      hotel_knowledge_faqs_path(hotel) => "FAQs",
      hotel_guest_amenities_path(hotel) => "Amenities",
      hotel_wifi_networks_path(hotel) => "Wi-Fi"
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

  it "keeps a validation error inside the Wi-Fi sheet" do
    post hotel_wifi_networks_path(hotel), params: {
      hotel_wifi_network: { label: "", ssid: "", security_type: "protected", access_scope: "checked_in_guests" }
    }, headers: sheet_submit_headers

    body = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:unprocessable_content)
    expect(body.at_css("turbo-frame#settings_action_sheet dialog#add-wifi-network-sheet")).to be_present
    expect(body.at_css("[role='alert']").text.squish).to include("Wi-Fi network could not be saved")
  end

  it "stacks every page body section in the shared rhythm" do
    document = create(:hotel_knowledge_document, hotel: hotel, category: "policy")

    [
      hotel_guest_content_path(hotel),
      hotel_knowledge_general_infos_path(hotel),
      hotel_guest_arrival_departure_path(hotel),
      hotel_knowledge_additional_information_path(hotel),
      hotel_knowledge_policies_path(hotel),
      hotel_guest_amenities_path(hotel),
      hotel_wifi_networks_path(hotel)
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
    {
      hotel_knowledge_policies_path(hotel) => [ "Add Policy" ],
      hotel_knowledge_faqs_path(hotel) => [ "Add FAQ" ],
      hotel_guest_amenities_path(hotel) => [ "Manage amenities" ],
      hotel_wifi_networks_path(hotel) => [ "Add network" ]
    }.each do |path, labels|
      get path

      body = Nokogiri::HTML(response.body).at_css("[data-testid='guest-content-body']")
      first_section = body.css("> div").find do |node|
        node.at_css("h2") &&
          !node["class"].to_s.include?("panel-page-header") &&
          node["data-testid"] != "guest-content-subtab-header"
      end
      expect(first_section.css(".panel-button").map { |button| button.text.squish }).to eq(labels), "#{path} section actions are wrong"
    end
  end

  it "keeps Property Summary and Additional Information on separate subtabs" do
    get hotel_knowledge_general_infos_path(hotel)

    body = Nokogiri::HTML(response.body).at_css("[data-testid='guest-content-body']")
    expect(body.css(".panel-page-header .panel-button")).to be_empty

    summary = body.at_css("[aria-labelledby='property-summary-heading']")
    expect(summary.css(".panel-button").map { |button| button.text.squish }).to eq([ "Property Settings" ])
    expect(body.at_css("[aria-label='Additional Information']")).to be_nil

    get hotel_knowledge_additional_information_path(hotel)
    body = response.parsed_body.at_css("[data-testid='guest-content-body']")

    additional = body.at_css("[aria-label='Additional Information']")
    expect(additional.css("h2").first.text.squish).to eq("Additional Information")
    section_header = additional.element_children.first
    expect(section_header.css(".panel-button").map { |button| button.text.squish }).to eq([ "Add Information" ])
    expect(body.at_css("[data-testid='guest-content-subtabs'] [data-tab-label='Additional Information'][aria-current='page']")).to be_present
  end
end
