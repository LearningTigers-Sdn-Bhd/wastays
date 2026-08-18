# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'HotelPortal::Profiles', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'live') }
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
      expect(response.body).to include(%(id="hotel-profile-section"))
      expect(response.body).to include(%(data-testid="settings-tabs"))
      expect(document.at_css("form[action='#{hotel_profile_path(hotel)}']")[:"data-turbo"]).to eq("false")
      expect(document.css(".panel-form-field .panel-input")).not_to be_empty
      description = document.at_css(".panel-form-field textarea[name='hotel[description]']")
      expect(description).to be_present
      expect(description[:placeholder]).to eq("Describe the property’s atmosphere, highlights, and guest experience.")
      expect(document.css(".panel-form-field .panel-select-menu")).not_to be_empty
      expect(document.css(".panel-form-field .panel-multi-select")).not_to be_empty
    end

    it 'lists the sections in column order with the read-only billing reference under hotel information' do
      get edit_hotel_profile_path(hotel)

      document = response.parsed_body
      expect(document.css("#hotel-profile-section h2").map { |heading| heading.text.squish }).to eq(
        [ "Hotel Information", "Billing Reference", "Hotel Location", "Property Contact", "Business Registration" ]
      )
      billing_reference = document.at_css("[data-testid='billing-reference'].panel-metric-card")
      expect(billing_reference.text.squish).to include("Billing Reference", "Effective setup fee")
    end

    it 'gives every editable section its own form and Save' do
      get edit_hotel_profile_path(hotel)

      document = response.parsed_body
      forms = document.css("form[action='#{hotel_profile_path(hotel)}']")
      expect(forms.map { |form| form.at_css("input[name='section']")[:value] }).to eq(
        %w[hotel-information hotel-location property-contact business-registration]
      )
      forms.each do |form|
        save = form.at_css("button[type='submit'][data-form-dirty-target='submit']")
        expect(save.text.squish).to eq("Save")
        # Enabled server-side: the Stimulus controller switches it off on connect,
        # so a page without JS is left with a Save that still works.
        expect(save[:disabled]).to be_nil

        cancel = form.at_css("button[type='reset'][data-form-dirty-target='cancel']")
        expect(cancel.text.squish).to eq("Cancel")
        # The mirror image: nothing to discard until something changes.
        expect(cancel[:hidden]).to be_present
      end
      expect(document.at_css("section#billing-reference button[type='submit']")).to be_nil
    end

    it 'leaves the album to its own page' do
      get edit_hotel_profile_path(hotel)

      expect(response.body).not_to include("hotel-photo-upload-sheet")
      expect(response.body).not_to include("hotel-published-photos")
    end
  end

  describe 'GET /hotel/:hotel_id/settings/property/hotel-album' do
    it 'renders the album page under the shared property header and tabs' do
      get hotel_album_path(hotel)

      expect(response).to have_http_status(:ok)
      document = response.parsed_body

      expect(document.css("h1").map { |heading| heading.text.squish }).to eq([ "Property Details Settings" ])
      expect(response.body).to include(%(data-testid="settings-tabs"))
      expect(response.body).to include(%(id="hotel-album-section"))
      expect(document.at_css("#hotel-album-section h2").text.squish).to eq("Hotel Album")
      expect(document.css(".panel-dropzone")).not_to be_empty
      expect(document.at_css("button[command='show-modal'][commandfor='hotel-photo-upload-sheet']").text.squish).to eq("Upload Photos")
      empty_album = document.at_css("#hotel-published-photos .panel-empty-state")
      expect(empty_album.at_css(".panel-empty-state__title").text.squish).to eq("No photos yet")
      # The state offers the upload itself rather than pointing at the section header.
      expect(empty_album.at_css("button[command='show-modal'][commandfor='hotel-photo-upload-sheet']").text.squish)
        .to eq("Upload photos")
      upload_sheet = document.at_css("dialog#hotel-photo-upload-sheet[data-panels-ui-sheet-side='right']")
      expect(upload_sheet.at_css("h2").text.squish).to eq("Upload Photos")
      expect(upload_sheet.at_css("footer").text.squish).to include("Discard All", "Confirm Upload")
    end

    it 'marks Hotel Album as the active tab, not Hotel Details' do
      get hotel_album_path(hotel)

      tabs = response.parsed_body.at_css("[data-testid='settings-tabs']")
      active = tabs.css("[aria-selected='true'], [aria-current='page']").map { |tab| tab.text.squish }
      expect(active).to eq([ "Hotel Album" ])
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

    it 'updates the contact numbers guests call, including the front desk landline' do
      patch hotel_profile_path(hotel), params: {
        hotel: { contact_phone: '012-8273581', fixed_line_number: '03-2144 1234' }
      }

      hotel.reload
      expect(hotel.contact_phone).to eq('012-8273581')
      expect(hotel.fixed_line_number).to eq('03-2144 1234')
    end

    it 'stores normalized business registration numbers' do
      patch hotel_profile_path(hotel), params: {
        hotel: {
          tin: ' c1234567890 ',
          ssm_number: '202301012345 (1234567-a)',
          local_government_name: '  Dewan   Bandaraya Kota Kinabalu ',
          local_government_license_number: ' pl/2026/001234 '
        }
      }

      hotel.reload
      expect(hotel.tin).to eq('C1234567890')
      expect(hotel.ssm_number).to eq('202301012345 (1234567-A)')
      expect(hotel.local_government_name).to eq('Dewan Bandaraya Kota Kinabalu')
      expect(hotel.local_government_license_number).to eq('PL/2026/001234')
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
