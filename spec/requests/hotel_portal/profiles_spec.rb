# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'HotelPortal::Profiles', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'approved') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner') }

  before do
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |p| p.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by(slug: 'manage_hotel_profile'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe 'GET /hotel/:hotel_id/profile/edit' do
    it 'renders the canonical hotel details page' do
      get edit_hotel_profile_path(hotel)

      expect(response).to have_http_status(:ok)
      document = response.parsed_body

      expect(document.css("h1").map { |heading| heading.text.squish }).to eq([ "Property Details Settings" ])
      expect(document.css("h2").map { |heading| heading.text.squish }).to include("Hotel Information", "Hotel Location", "Hotel Album")
      expect(response.body).to include(%(id="hotel-profile-section"))
      expect(response.body).to include(%(data-testid="settings-tabs"))
      expect(document.at_css("form[action='#{hotel_profile_path(hotel)}']")[:"data-turbo"]).to eq("false")
      expect(document.css(".panel-form-field .panel-input")).not_to be_empty
      description = document.at_css(".panel-form-field textarea[name='hotel[description]']")
      expect(description).to be_present
      expect(description[:placeholder]).to eq("Describe the property’s atmosphere, highlights, and guest experience.")
      expect(document.css(".panel-form-field .panel-select-menu")).not_to be_empty
      expect(document.css(".panel-form-field .panel-multi-select")).not_to be_empty
      expect(document.css(".panel-dropzone")).not_to be_empty
      expect(document.at_css("button[command='show-modal'][commandfor='hotel-photo-upload-sheet']").text.squish).to eq("Upload Photos")
      expect(document.at_css("#hotel-published-photos.min-h-40 p.min-h-40").text.squish).to include("No published photos yet")
      upload_sheet = document.at_css("dialog#hotel-photo-upload-sheet[data-panels-ui-sheet-side='right']")
      expect(upload_sheet.at_css("h2").text.squish).to eq("Upload Photos")
      expect(upload_sheet.at_css("footer").text.squish).to include("Discard All", "Confirm Upload")
      billing_reference = document.at_css("[data-testid='billing-reference'].panel-metric-card")
      expect(billing_reference.text.squish).to include("Billing Reference", "Effective setup fee")
    end
  end

  describe 'PATCH /hotel/profile' do
    it 'updates hotel profile including star rating and google map link' do
      patch hotel_profile_path(hotel), params: {
        hotel: {
          name: 'Updated Hotel Name',
          description: 'A peaceful city retreat with locally inspired hospitality.',
          star_rating: '5',
          google_map_link: 'https://www.google.com/maps/place/Updated+Hotel'
        }
      }

      hotel.reload
      expect(response).to redirect_to(edit_hotel_profile_path(hotel))
      follow_redirect!
      expect(response.body).to include('Hotel profile updated successfully.')

      expect(hotel.name).to eq('Updated Hotel Name')
      expect(hotel.description).to eq('A peaceful city retreat with locally inspired hospitality.')
      expect(hotel.star_rating).to eq(5)
      expect(hotel.google_map_link).to eq('https://www.google.com/maps/place/Updated+Hotel')
    end

    it "redirects Turbo submissions to an HTML page with a success toast" do
      patch hotel_profile_path(hotel), params: {
        hotel: {
          name: "Turbo Updated Hotel",
          city: hotel.city,
          country: hotel.country
        }
      }, headers: { "Accept" => Mime[:turbo_stream].to_s }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(edit_hotel_profile_path(hotel.reload))

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:html].to_s)
      expect(response.body).to include("Hotel profile updated successfully.")
      expect(hotel.name).to eq("Turbo Updated Hotel")
    end

    it "renders the canonical hotel details page when profile update is invalid" do
      patch hotel_profile_path(hotel), params: {
        hotel: {
          name: "",
          city: hotel.city,
          country: hotel.country
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(%(id="hotel-profile-section"))
      expect(response.body).to include(%(data-testid="settings-tabs"))
      invalid_fields = response.parsed_body.css(".panel-form-field[data-invalid='true']")
      expect(invalid_fields.map { |field| field.text.squish }).to include(a_string_including("Hotel Name"))
    end
  end
end
