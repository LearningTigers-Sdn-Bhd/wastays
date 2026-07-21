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

    it "prepends explicit move and date actions for a Timeline-origin drawer" do
      booking.update_column(:status, "completed")

      get hotel_booking_transaction_show_booking_path(hotel, booking), params: { source: "stay_view", return_to: }

      document = Nokogiri::HTML(response.body)
      actions_button = document.css("button").find { |button| button.text.squish == "Actions" }
      menu = actions_button.parent.at_css("[role='menu']")
      expect(response).to have_http_status(:success)
      expect(menu.css("a[role='menuitem']").map { |item| item.text.squish }).to eq([ "Move or reassign", "Change dates" ])

      expected = {
        "Move or reassign" => edit_hotel_stay_view_booking_move_path(hotel, booking),
        "Change dates" => edit_hotel_stay_view_booking_dates_path(hotel, booking)
      }
      menu.css("a[role='menuitem']").each do |item|
        uri = URI.parse(item["href"])
        query = Rack::Utils.parse_nested_query(uri.query)
        expect(uri.path).to eq(expected.fetch(item.text.squish))
        expect(query).to include("source" => "stay_view", "return_to" => return_to)
        expect(query).not_to have_key("proposal")
        expect(item["data-turbo-frame"]).to eq("offcanvas_drawer")
        expect(item["data-offcanvas-variant"]).to eq("compact-right")
      end
    end

    it "does not add Stay View actions to an ordinary booking drawer" do
      get hotel_booking_transaction_show_booking_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("Move or reassign", "Change dates")
    end
  end
end
