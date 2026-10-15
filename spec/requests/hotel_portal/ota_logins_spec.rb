# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::OtaLogins", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "setup") }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }
  let(:attributes) do
    {
      channel_name: "Booking.com", property_code: "BC-42", username: "booking-user",
      password: "private-ota-password", market_manager_name: "Amina",
      market_manager_phone: "+60123456789", market_manager_email: "amina@example.com"
    }
  end

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    RolePermission.create!(role: role, permission: permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "shows a labelled form in the settings action sheet" do
    get hotel_new_ota_login_path(hotel)

    expect(response).to have_http_status(:ok)
    document = response.parsed_body
    expect(document.at_css("turbo-frame#settings_action_sheet dialog")).to be_present
    expect(document.text).to include("Add OTA Login")
    form = document.at_css("form[action='#{hotel_ota_logins_path(hotel)}']")
    expect(form.css("label").map { |label| label.text.squish }).to include("Channel * (required)", "Property ID", "Username", "Password", "Market manager", "Market manager phone", "Market manager email")
    expect(form.css("input[required]").map { |input| input["name"] }).to eq([ "hotel_ota_credential[channel_name]" ])
    expect(form.at_css("input[type='password']")["autocomplete"]).to eq("new-password")
    expect(document.at_css("button[type='submit'][form='add-ota-login-form']").text).to eq("Add OTA Login")
    expect(document.at_css("button[data-action='click->ui--sheet#close']").text).to eq("Cancel")
  end

  it "adds a login for the current hotel and ignores ownership and status overrides" do
    foreign_hotel = create(:hotel, account: account)

    expect do
      post hotel_ota_logins_path(hotel), params: { hotel_ota_credential: attributes.merge(hotel_id: foreign_hotel.id, status: "processed") }
    end.to change(hotel.hotel_ota_credentials, :count).by(1)

    expect(response).to redirect_to(hotel_ota_logins_settings_path(hotel))
    expect(hotel.hotel_ota_credentials.last).to have_attributes(attributes.except(:password).merge(hotel_id: hotel.id, status: "pending"))
    expect(foreign_hotel.hotel_ota_credentials).to be_empty
    follow_redirect!
    expect(response.body).to include("OTA login added.", "Booking.com")
    expect(response.body).not_to include(attributes[:password])
  end

  [
    [ "blank channel", { channel_name: " " }, "can't be blank" ],
    [ "invalid email", { market_manager_email: "invalid" }, "is invalid" ]
  ].each do |description, overrides, error|
    it "rejects #{description} and preserves inputs without echoing the password" do
      expect do
        post hotel_ota_logins_path(hotel), params: { hotel_ota_credential: attributes.merge(overrides) }
      end.not_to change(HotelOtaCredential, :count)

      expect(response).to have_http_status(:unprocessable_content)
      document = response.parsed_body
      expect(document.text).to include(error, "Re-enter the password before saving.")
      expect(document.at_css("input[name='hotel_ota_credential[username]']")["value"]).to eq("booking-user")
      expect(document.at_css("input[type='password']")["value"]).to be_blank
      expect(response.body).not_to include(attributes[:password])
    end
  end

  it "rejects a duplicate channel regardless of capitalization" do
    create(:hotel_ota_credential, hotel: hotel, channel_name: "booking.COM")

    expect do
      post hotel_ota_logins_path(hotel), params: { hotel_ota_credential: attributes }
    end.not_to change(HotelOtaCredential, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.text).to include("already has credentials for this property")
  end

  it "closes the sheet and returns to the OTA table after a Turbo save" do
    post hotel_ota_logins_path(hotel), params: { hotel_ota_credential: attributes },
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "settings_action_sheet" }

    expect(response).to have_http_status(:ok)
    stream = Nokogiri::HTML(response.body).at_css("turbo-stream[action='complete_sheet']")
    expect(stream["target"]).to eq("settings_action_sheet")
    expect(stream["url"]).to eq(hotel_ota_logins_settings_path(hotel))
    expect(response.body).not_to include(attributes[:password])
  end

  it "keeps validation errors inside the requested sheet frame" do
    post hotel_ota_logins_path(hotel), params: { hotel_ota_credential: attributes.merge(channel_name: "") },
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "settings_action_sheet" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.media_type).to eq("text/html")
    expect(response.parsed_body.at_css("turbo-frame#settings_action_sheet dialog")).to be_present
    expect(response.parsed_body.text).to include("can't be blank", "Re-enter the password before saving.")
    expect(response.body).not_to include(attributes[:password])
  end

  it "denies form and create access without hotel profile permission" do
    RolePermission.where(role: role).destroy_all

    get hotel_new_ota_login_path(hotel)
    expect(response).to have_http_status(:redirect)
    expect do
      post hotel_ota_logins_path(hotel), params: { hotel_ota_credential: attributes }
    end.not_to change(HotelOtaCredential, :count)
    expect(response).to have_http_status(:redirect)
  end
end
