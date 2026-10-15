# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::UserProfiles", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:, status: "live") }
  let(:user) { create(:user, account:) }

  before do
    create(:user_hotel_access, user:, hotel:, role: create(:role, account:))
    sign_in_as(user)
  end

  it "renders the form with the time zone combobox" do
    get edit_hotel_user_profile_path(hotel)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Change password")
    expect(response.body).to include("Search and select a time zone")
  end

  it "saves the time zone" do
    patch hotel_user_profile_path(hotel), params: { user: { name: user.name, time_zone: "Singapore" } }

    expect(response).to redirect_to(edit_hotel_user_profile_path(hotel))
    expect(user.reload.time_zone).to eq("Singapore")
  end
end

RSpec.describe "HotelPortal::UserProfiles sections", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:, status: "live") }
  let(:user) { create(:user, account:, password: "first-password-123") }

  before do
    create(:user_hotel_access, user:, hotel:, role: create(:role, account:))
    sign_in_as(user)
  end

  it "renders details and password as two forms with Save disabled until a change" do
    get edit_hotel_user_profile_path(hotel)

    page = Nokogiri::HTML(response.body)
    forms = page.css("form[data-controller='form-dirty']")

    expect(forms.map { |form| form["id"] }).to eq(%w[profile-details-form profile-password-form])
    expect(forms.map { |form| form.at_css("button[type=submit]")["disabled"] }).to all(be_present)
  end

  it "saves the password form without touching the details" do
    patch hotel_user_profile_path(hotel), params: { user: { current_password: "first-password-123", password: "new-password-456", password_confirmation: "new-password-456" } }

    expect(response).to redirect_to(edit_hotel_user_profile_path(hotel))
    expect(user.reload.authenticate("new-password-456")).to eq(user)
  end
end
