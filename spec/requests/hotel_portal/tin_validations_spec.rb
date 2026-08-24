# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::TinValidations", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:hotel) { create(:hotel, account: account, status: "live") }
  let!(:setting) { create(:e_invoice_setting, hotel: hotel) }
  let(:client) { instance_double(MyInvois::MockClient) }

  def grant(*slugs)
    role = create(:role, account: account, slug: "staff-#{SecureRandom.hex(4)}")
    slugs.each do |slug|
      permission = Permission.find_or_create_by!(slug: slug) { |p| p.name = slug.titleize }
      RolePermission.find_or_create_by!(role: role, permission: permission)
    end
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
  end

  before { allow(MyInvois::ClientFactory).to receive(:build).and_return(client) }

  context "as someone who can see bookings" do
    before do
      grant("view_bookings")
      sign_in_as(user)
    end

    it "confirms a matching tax number" do
      allow(client).to receive(:validate_tin).and_return({ "status" => "Valid" })

      post hotel_validate_tin_path(hotel), params: { tin: "IG12345678901", id_value: "880101015432", document_type: "ic" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("valid")
    end

    it "reports a mismatch so the desk can correct it there and then" do
      allow(client).to receive(:validate_tin).and_return({ "status" => "Invalid" })

      post hotel_validate_tin_path(hotel), params: { tin: "IG1", id_value: "880101015432", document_type: "ic" }

      expect(response.parsed_body["status"]).to eq("invalid")
    end

    # Checking a tax number must never become a reason a check-in fails.
    it "answers without error when LHDN is unreachable" do
      allow(client).to receive(:validate_tin)
        .and_raise(MyInvois::Client::ApiError.new("down", code: "503"))

      post hotel_validate_tin_path(hotel), params: { tin: "IG12345678901", id_value: "880101015432" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("unknown")
    end
  end

  it "is closed to staff without booking access" do
    grant("manage_hotel_profile")
    sign_in_as(user)

    post hotel_validate_tin_path(hotel), params: { tin: "IG12345678901", id_value: "880101015432" }

    expect(response).not_to have_http_status(:ok)
  end
end
