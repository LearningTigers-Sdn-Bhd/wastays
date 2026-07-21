# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal booking show actions", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel, guest_country: "Malaysia") }

  before do
    permission = Permission.find_by(slug: "manage_bookings") || create(:permission, slug: "manage_bookings", name: "Manage Bookings")
    create(:role_permission, role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "tourism tax voucher print menu entry" do
    it "shows an active link whenever booking owes tourism tax" do
      booking.update!(guest_country: "Singapore", tourism_tax_amount: 20.0, tourism_tax_applied: true, tax_lines: [ { "type" => "tourism_tax", "amount" => 20.0 } ])

      get hotel_booking_transaction_show_booking_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Issue Tourism Tax Voucher")
      expect(response.body).to include(issue_hotel_booking_tourism_tax_voucher_path(hotel, booking))
    end

    it "omits entry when booking has no tourism tax" do
      get hotel_booking_transaction_show_booking_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("Tourism Tax Voucher")
    end
  end

  describe "Stay View actions" do
    let(:return_to) { hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 7) }

    it "prepends intent-scoped stay-editing actions for a Timeline-origin drawer" do
      get hotel_booking_transaction_show_booking_path(hotel, booking), params: { source: "stay_view", return_to: }

      document = Nokogiri::HTML(response.body)
      actions_button = document.css("button").find { |button| button.text.squish == "Actions" }
      menu = actions_button.parent.at_css("[role='menu']")
      expect(response).to have_http_status(:success)
      item = menu.css("a[role='menuitem']").find { |link| link.text.squish == "Change rate" }
      uri = URI.parse(item["href"])
      query = Rack::Utils.parse_nested_query(uri.query)
      expect(uri.path).to eq(hotel_booking_action_edit_rate_path(hotel, booking))
      expect(query).to include("source" => "stay_view", "return_to" => return_to)
      expect(query).not_to have_key("proposal")
      expect(item["data-turbo-frame"]).to eq("booking_action_sheet")
    end

    it "does not add Stay View actions to an ordinary booking drawer" do
      get hotel_booking_transaction_show_booking_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("Change rate")
    end
  end
end
