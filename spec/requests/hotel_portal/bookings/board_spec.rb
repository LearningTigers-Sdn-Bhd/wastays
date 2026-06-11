# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Board", type: :request do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: [ "101" ]) }

  def grant_permission(role, slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  def sign_in_with_permissions(*slugs)
    user = create(:user)
    role = create(:role, account: hotel.account)
    slugs.each { |slug| grant_permission(role, slug) }
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
    user
  end

  describe "GET /hotel/:hotel_id/bookings/board" do
    let!(:booking) { create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 2.days) }

    before do
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
    end

    it "responds successfully and includes the required modal structures" do
      sign_in_with_permissions("manage_bookings")

      get board_hotel_bookings_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("id=\"offcanvas_drawer_container\"")
      expect(response.body).to include("Booking Timeline Board")
      expect(response.body).to include("id=\"booking-timeline-board-extend-duration-overlay\"")
    end

    it "renders accessible move and resize controls for booking managers" do
      sign_in_with_permissions("manage_bookings")

      get board_hotel_bookings_path(hotel)

      booking_block = response.parsed_body.at_css("[data-id='#{booking.id}']")
      expect(booking_block).to be_present
      expect(booking_block["role"]).to eq("button")
      expect(booking_block["tabindex"]).to eq("0")
      expect(booking_block["aria-label"]).to include(booking.guest_name)
      expect(booking_block["draggable"]).to eq("true")
      expect(booking_block["data-action"]).to include("dragstart->booking-timeline#onDragStart")
      expect(booking_block.at_css("[data-action*='onDragHandleMouseDown']")).to be_present
      expect(booking_block.at_css("[data-action*='onResizeStart']")).to be_present
      expect(response.parsed_body.at_css("[aria-label^='Create booking for room 101']")).to be_present
    end

    it "renders a read-only booking link without management affordances" do
      sign_in_with_permissions("view_reservation_board", "view_bookings")

      get board_hotel_bookings_path(hotel)

      booking_link = response.parsed_body.at_css("a[href='#{hotel_booking_path(hotel, booking)}']")
      expect(booking_link).to be_present
      expect(booking_link["aria-label"]).to include(booking.guest_name)
      expect(response.parsed_body.at_css("[data-id='#{booking.id}']")).to be_nil
      expect(response.parsed_body.at_css("[data-booking-timeline-target='dragHandle']")).to be_nil
      expect(response.parsed_body.at_css("[data-booking-timeline-target='resizeHandle']")).to be_nil
      expect(response.parsed_body.at_css("[aria-label^='Create booking for room 101']")).to be_nil
      expect(response.body).not_to include("booking-timeline-board-extend-duration-overlay")
    end

    it "displays rates in empty cells when a rate plan is present" do
      rate_plan = create(:rate_plan, room_type: room_type, name: "Standard Rate")
      create(:room_rate, rate_plan: rate_plan, room_type: room_type, date: Date.current + 3.days, price: 250, currency: "MYR")

      sign_in_with_permissions("manage_bookings")

      get board_hotel_bookings_path(hotel, filters: { rate_plan_name: "Standard Rate" })

      expect(response).to have_http_status(:success)
      expect(response.body).to include("250")
    end
  end
end
