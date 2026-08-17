# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::ProfileIcon", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "setup") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") do |record|
      record.name = "Manage Hotel Profile"
    end
    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "renders the single-image hotel icon field in Hotel Information" do
    get edit_hotel_profile_path(hotel)

    field = response.parsed_body.at_css("#hotel-information .panel-form-field[data-testid='hotel-icon-field']")
    expect(field).to be_present
    expect(field.at_css("input[name='hotel[icon]'][type='file']")).to be_present
    expect(field.at_css("input[name='hotel[remove_icon]'][value='0']")).to be_present
  end

  it "uploads and replaces a hotel icon even if a stale remove flag is submitted" do
    patch hotel_profile_path(hotel), params: {
      section: "hotel-information",
      hotel: { icon: uploaded_icon("first.jpg"), remove_icon: "0" }
    }

    expect(response).to redirect_to("#{edit_hotel_profile_path(hotel)}#hotel-information")
    expect(hotel.reload.icon.filename.to_s).to eq("first.jpg")

    patch hotel_profile_path(hotel), params: {
      section: "hotel-information",
      hotel: { icon: uploaded_icon("replacement.jpg"), remove_icon: "1" }
    }

    expect(response).to redirect_to("#{edit_hotel_profile_path(hotel)}#hotel-information")
    expect(hotel.reload.icon.filename.to_s).to eq("replacement.jpg")
    expect(ActiveStorage::Attachment.where(record: hotel, name: "icon").count).to eq(1)
  end

  it "stages removal until a valid profile save succeeds" do
    hotel.icon.attach(uploaded_icon("existing.jpg"))

    patch hotel_profile_path(hotel), params: {
      section: "hotel-information",
      hotel: { name: "", remove_icon: "1" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(hotel.reload.icon).to be_attached

    patch hotel_profile_path(hotel), params: {
      section: "hotel-information",
      hotel: { name: hotel.name, remove_icon: "1" }
    }

    expect(response).to redirect_to("#{edit_hotel_profile_path(hotel)}#hotel-information")
    expect(hotel.reload.icon).not_to be_attached
  end

  it "rejects an unsupported icon without removing the existing attachment" do
    hotel.icon.attach(uploaded_icon("existing.jpg"))

    patch hotel_profile_path(hotel), params: {
      section: "hotel-information",
      hotel: {
        icon: Rack::Test::UploadedFile.new(Rails.root.join("public/icon.svg"), "image/svg+xml"),
        remove_icon: "1"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must be a PNG, JPG, or WebP image")
    expect(hotel.reload.icon.filename.to_s).to eq("existing.jpg")
  end

  def uploaded_icon(filename)
    Rack::Test::UploadedFile.new(
      Rails.root.join("spec/fixtures/files/sample_image.jpg"),
      "image/jpeg",
      false,
      original_filename: filename
    )
  end
end
