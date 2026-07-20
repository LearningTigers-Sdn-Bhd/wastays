require "rails_helper"

RSpec.describe "HotelPortal::FrontDesk", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }

  before do
    UserHotelAccess.create!(user:, hotel:, role:)
    sign_in_as(user)
  end

    def grant_arrival_permission
    permission = Permission.find_or_create_by!(slug: "manage_guest_arrival") { |record| record.name = "Manage Guest Arrival" }
    role.permissions << permission
  end

  def booking(attributes = {})
    create(:booking, { hotel:, guest_name: "Aisha Tan", guest_email: "aisha@example.com", guest_phone: "+60123456789" }.merge(attributes))
  end

  def hotel_today
    Time.current.in_time_zone(hotel.hotel_time_zone).to_date
  end

  describe "GET /hotel/:hotel_id/front-desk" do
    it "redirects unauthenticated users to login" do
      delete logout_path

      get hotel_front_desk_path(hotel)

      expect(response).to redirect_to(login_path)
    end

    def grant_booking_permission
      %w[view_bookings manage_bookings].each do |slug|
        permission = Permission.find_or_create_by!(slug:) { |record| record.name = slug.humanize }
        role.permissions << permission unless role.permissions.exists?(permission.id)
      end
    end

    it "logs out suspended accounts" do
      user.account.update!(status: "suspended")

      get hotel_front_desk_path(hotel)

      expect(response).to redirect_to(login_path)
      follow_redirect!
      expect(response.body).to include("Your account has been suspended. Please contact support.")
    end

    it "does not expose another hotel's records" do
      own_booking = booking(status: "checked_in", confirmation_token: "OWN-STAY", checked_in_at: Time.current)
      other_booking = create(:booking, hotel: other_hotel, status: "checked_in", confirmation_token: "OTHER-STAY", checked_in_at: Time.current)

      get hotel_front_desk_path(hotel), params: { tab: "in_house" }

      expect(response.body).to include(own_booking.confirmation_token)
      expect(response.body).not_to include(other_booking.confirmation_token)
    end

    it "defaults to arrivals, then in-house, then departures" do
      grant_arrival_permission
      get hotel_front_desk_path(hotel)
      expect(response.body).to include("active-tab:arrivals")

      role.permissions.delete_all
      get hotel_front_desk_path(hotel)
      expect(response.body).to include("active-tab:in_house")
    end

    it "hides arrivals and falls back to in-house without hotel-scoped arrival permission" do
      arrival = booking(status: "confirmed", confirmation_token: "RESTRICTED-ARRIVAL", check_in: hotel_today)
      stay = booking(status: "checked_in", confirmation_token: "VISIBLE-STAY", checked_in_at: Time.current)

      get hotel_front_desk_path(hotel), params: { tab: "arrivals" }

      expect(response.body).to include("active-tab:in_house")
      expect(response.body).to include(stay.confirmation_token)
      expect(response.body).not_to include(arrival.confirmation_token)
      expect(response.body).not_to include("metric:arrivals")
    end

    it "does not grant arrivals from an account-global permission" do
      permission = Permission.find_or_create_by!(slug: "manage_guest_arrival") { |record| record.name = "Manage Guest Arrival" }
      global_role = create(:role, account: hotel.account)
      global_role.permissions << permission
      user.roles << global_role
      arrival = booking(status: "confirmed", confirmation_token: "GLOBAL-ONLY-ARRIVAL", check_in: hotel_today)

      get hotel_front_desk_path(hotel), params: { tab: "arrivals" }

      expect(response.body).to include("active-tab:in_house")
      expect(response.body).not_to include("metric:arrivals")
      expect(response.body).not_to include(arrival.confirmation_token)
    end

    it "makes in-house and departures available without arrival permission" do
      get hotel_front_desk_path(hotel), params: { tab: "departures" }

      expect(response.body).to include("active-tab:departures")
      expect(response.parsed_body.at_css("#reservation-sections-tab-in_house")&.[]("href")).to include("tab=in_house")
    end

    it "normalizes invalid state safely" do
      get hotel_front_desk_path(hotel), params: {
        tab: "invalid", view: "invalid", arrival_date: "nope", room_assignment: "invalid",
        in_house_page: "-3", arrival_page: "x", departure_page: "0"
      }

      expect(response.body).to include("active-tab:in_house")
      expect(response.body).to include("active-view:rooms")
      expect(response.body).to include("page:1")
    end

    it "defaults to the rooms view" do
      get hotel_front_desk_path(hotel)

      expect(response.body).to include("active-view:rooms")
      expect(response.parsed_body.at_css("[aria-label='Reservation view'] a[aria-current='page']")&.text).to include("Rooms")
    end

    it "hides today reset until arrivals or departures use another date" do
      grant_arrival_permission
      today = hotel_today.iso8601

      %w[arrivals departures].each do |tab|
        get hotel_front_desk_path(hotel), params: { tab: }
        expect(response.parsed_body.at_css("a[aria-label='Reset to today']")).to be_nil

        prefix = tab == "arrivals" ? "arrival" : "departure"
        get hotel_front_desk_path(hotel), params: {
          tab:, "#{prefix}_start_date" => "2026-07-14", "#{prefix}_end_date" => "2026-07-15"
        }
        expect(response.parsed_body.at_css("a[aria-label='Reset to today']")&.[]("href")).to include(
          "#{prefix}_start_date=#{today}", "#{prefix}_end_date=#{today}"
        )
      end
    end

    it "rejects structured state inputs with canonical defaults" do
      grant_arrival_permission

      get hotel_front_desk_path(hotel), params: {
        tab: [ "departures" ], view: [ "rooms" ], arrival_date: [ "2026-07-15" ],
        arrival_q: [ "Aisha" ], in_house_query: [ "Aisha" ], departure_query: [ "Aisha" ],
        room_assignment: [ "assigned" ], arrival_page: [ "2" ], in_house_page: [ "2" ], departure_page: [ "2" ]
      }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("active-tab:arrivals")
      expect(response.body).to include("active-view:rooms")
      expect(response.body).to include("page:1")
    end

    it "uses arrivals search, ordering, and 25-row pagination" do
      grant_arrival_permission
      matching = booking(status: "confirmed", confirmation_token: "ARRIVAL-MATCH", check_in: hotel_today, created_at: 2.days.ago)
      excluded = booking(status: "confirmed", confirmation_token: "ARRIVAL-EXCLUDED", check_in: hotel_today)
      25.times { |index| booking(status: "confirmed", confirmation_token: "ARRIVAL-#{index}", check_in: hotel_today) }

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", arrival_q: "MATCH", arrival_page: 1 }
      expect(response.body).to include(matching.confirmation_token)
      expect(response.body).not_to include(excluded.confirmation_token)

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", arrival_page: 2 }
      expect(response.body).not_to include(matching.confirmation_token)
      expect(response.body).to include("ARRIVAL-24")
    end

    it "keeps calendar ranges independent between tabs" do
      grant_arrival_permission
      grant_booking_permission
      arrival = booking(status: "confirmed", confirmation_token: "ARRIVAL-RANGE", check_in: Date.new(2026, 7, 15))
      booking_record = booking(status: "confirmed", confirmation_token: "BOOKING-RANGE", check_in: Date.new(2026, 7, 16))

      get hotel_front_desk_path(hotel), params: {
        tab: "arrivals", arrival_start_date: "2026-07-15", arrival_end_date: "2026-07-15"
      }
      expect(response.body).to include(arrival.confirmation_token)

      document = Nokogiri::HTML(response.body)
      bookings_link = document.css("[aria-label='Reservation sections'] a").find { |link| link.text.include?("Bookings") }

      get bookings_link["href"]
      expect(response.body).to include(booking_record.confirmation_token)
      expect(response.body).not_to include('name="booking_start_date" value="2026-07-15"')
    end

    it "keeps legacy date ranges working while scoped dates take precedence" do
      grant_arrival_permission
      legacy_arrival = booking(status: "confirmed", confirmation_token: "LEGACY-ARRIVAL", check_in: Date.new(2026, 7, 15))
      scoped_arrival = booking(status: "confirmed", confirmation_token: "SCOPED-ARRIVAL", check_in: Date.new(2026, 7, 16))

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", start_date: "2026-07-15", end_date: "2026-07-15" }
      expect(response.body).to include(legacy_arrival.confirmation_token)
      expect(response.body).not_to include(scoped_arrival.confirmation_token)

      get hotel_front_desk_path(hotel), params: {
        tab: "arrivals", start_date: "2026-07-15", end_date: "2026-07-15",
        arrival_start_date: "2026-07-16", arrival_end_date: "2026-07-16"
      }
      expect(response.body).to include(scoped_arrival.confirmation_token)
      expect(response.body).not_to include(legacy_arrival.confirmation_token)
    end

    it "resets arrivals to hotel-local today while preserving independent filters" do
      grant_arrival_permission

      hotel.update!(time_zone: "Kuala Lumpur")
      travel_to(Time.utc(2026, 7, 15, 18, 30)) do
        today = booking(status: "confirmed", confirmation_token: "LOCAL-TODAY", check_in: hotel.hotel_time_zone.local(2026, 7, 16, 15))
        get hotel_front_desk_path(hotel), params: {
          tab: "arrivals", view: "rooms", arrival_q: "LOCAL",
          arrival_start_date: "2026-07-14", arrival_end_date: "2026-07-14", arrival_page: 2,
          in_house_query: "Stay", in_house_page: 3, departure_query: "Departed", departure_page: 4
        }

        reset_link = response.parsed_body.at_css("a[aria-label='Reset to today']")
        expect(reset_link).to be_present
        expect(reset_link["href"]).to include(
          "tab=arrivals", "view=rooms", "arrival_q=LOCAL",
          "arrival_start_date=2026-07-16", "arrival_end_date=2026-07-16",
          "in_house_query=Stay", "in_house_page=3", "departure_query=Departed", "departure_page=4"
        )
        expect(reset_link["href"]).not_to include("arrival_page")

        get reset_link["href"]
        expect(response.body).to include(today.confirmation_token)
        expect(response.parsed_body.at_css("input[name='arrival_start_date']")["value"]).to eq("2026-07-16")
        expect(response.parsed_body.at_css("input[name='arrival_end_date']")["value"]).to eq("2026-07-16")
      end
    end

    it "clears booking dates and page while preserving unrelated state" do
      grant_booking_permission

      get hotel_front_desk_path(hotel), params: {
        tab: "bookings", view: "list", booking_query: "Aisha",
        booking_start_date: "2026-07-14", booking_end_date: "2026-07-15", booking_page: 2,
        in_house_query: "Stay", in_house_page: 3
      }

      clear_link = response.parsed_body.at_css("a[aria-label='Clear dates']")
      expect(clear_link["href"]).to include("tab=bookings", "view=list", "booking_query=Aisha", "in_house_query=Stay", "in_house_page=3")
      expect(clear_link["href"]).not_to include("booking_start_date", "booking_end_date", "booking_page")
    end

    it "resets departure dates to hotel-local today" do
      hotel.update!(time_zone: "Kuala Lumpur")

      travel_to(Time.utc(2026, 7, 15, 18, 30)) do
        get hotel_front_desk_path(hotel), params: {
          tab: "departures", view: "list", departure_query: "Aisha",
          departure_start_date: "2026-07-14", departure_end_date: "2026-07-15", departure_page: 2
        }

        reset_link = response.parsed_body.at_css("a[aria-label='Reset to today']")
        expect(reset_link["href"]).to include("departure_start_date=2026-07-16", "departure_end_date=2026-07-16", "departure_query=Aisha")
        expect(reset_link["href"]).not_to include("departure_page")
      end
    end

    it "hides Clear dates without date controls and uses button view controls" do
      get hotel_front_desk_path(hotel), params: { tab: "in_house", view: "list" }

      document = response.parsed_body
      expect(document.at_css("a[aria-label='Clear dates'], a[aria-label='Reset to today']")).to be_nil
      view_group = document.at_css(".panel-button-group[aria-label='Reservation view']")
      expect(view_group).to be_present
      expect(view_group.css("a.panel-button").map { |link| link.text.squish }).to eq(%w[Rooms List])
      active_links = view_group.css("a.panel-button[aria-current='page']")
      expect(active_links.one?).to be(true)
      expect(active_links.first.text).to include("List")
      expect(active_links.first["data-variant"]).to eq("secondary")
      expect(active_links.first["data-size"]).to eq("lg")
      inactive_link = view_group.at_css("a.panel-button[href*='view=rooms']")
      expect(inactive_link["data-variant"]).to eq("neutral")
      expect(inactive_link["data-size"]).to eq("lg")
      expect(inactive_link["aria-current"]).to be_nil
      expect(view_group.css("svg[aria-hidden='true']").size).to eq(2)
      expect(document.at_css("#reservation-view.tabs-root")).to be_nil
    end

    it "does not preserve structured date parameters in tab links" do
      grant_arrival_permission

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", arrival_start_date: [ "2026-07-15" ], arrival_end_date: { date: "2026-07-15" } }

      document = Nokogiri::HTML(response.body)
      document.css("[aria-label='Reservation sections'] a, [aria-label='Reservation view'] a").each do |link|
        expect(link["href"]).not_to include("arrival_start_date", "arrival_end_date")
      end
    end

    it "orders arrivals by created_at ascending with a 25-record page boundary" do
      grant_arrival_permission
      27.times do |index|
        booking(
          status: "confirmed",
          confirmation_token: format("ARRIVAL-ORDER-%02d", index),
          check_in: hotel_today,
          created_at: Time.zone.local(2026, 7, 15, 9, 0) + index.minutes
        )
      end

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", view: "list", arrival_page: 1 }

      page_one = response.body.scan(/booking:(ARRIVAL-ORDER-\d+)/).flatten
      expect(page_one).to eq((0...25).map { |index| format("ARRIVAL-ORDER-%02d", index) })

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", view: "list", arrival_page: 2 }

      expect(response.body.scan(/booking:(ARRIVAL-ORDER-\d+)/).flatten).to eq(%w[ARRIVAL-ORDER-25 ARRIVAL-ORDER-26])
    end

    it "keeps equal-created arrivals on stable id-ordered pages" do
      grant_arrival_permission
      timestamp = Time.zone.local(2026, 7, 15, 9, 0)
      27.times do |index|
        booking(
          status: "confirmed",
          confirmation_token: format("ARRIVAL-TIE-%02d", index),
          check_in: hotel_today,
          created_at: timestamp
        )
      end

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", view: "list", arrival_page: 1 }
      expect(response.body.scan(/booking:(ARRIVAL-TIE-\d+)/).flatten).to eq((0...25).map { |index| format("ARRIVAL-TIE-%02d", index) })

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", view: "list", arrival_page: 2 }
      expect(response.body.scan(/booking:(ARRIVAL-TIE-\d+)/).flatten).to eq(%w[ARRIVAL-TIE-25 ARRIVAL-TIE-26])
    end

    it "uses in-house search, room assignment filter, ordering, and pagination" do
      unassigned = booking(status: "checked_in", confirmation_token: "INHOUSE-UNASSIGNED", checked_in_at: 2.days.ago)
      assigned = booking(status: "checked_in", confirmation_token: "INHOUSE-ASSIGNED", checked_in_at: Time.current)
      room_type = create(:room_type, hotel:)
      BookingRoom.create!(booking: assigned, room_type:, room_type_snapshot: { "name" => room_type.name }, subtotal: assigned.total_amount)

      get hotel_front_desk_path(hotel), params: { tab: "in_house", room_assignment: "unassigned", in_house_query: "INHOUSE", in_house_page: 1 }
      expect(response.body).to include(unassigned.confirmation_token)
      expect(response.body).not_to include(assigned.confirmation_token)
    end

    it "orders in-house records by checked_in_at then created_at descending" do
      oldest = booking(status: "checked_in", confirmation_token: "INHOUSE-ORDER-OLDEST", checked_in_at: Time.zone.local(2026, 7, 15, 8, 0), created_at: Time.zone.local(2026, 7, 15, 8, 0))
      earlier = booking(status: "checked_in", confirmation_token: "INHOUSE-ORDER-EARLIER", checked_in_at: Time.zone.local(2026, 7, 15, 9, 0), created_at: Time.zone.local(2026, 7, 15, 9, 0))
      later = booking(status: "checked_in", confirmation_token: "INHOUSE-ORDER-LATER", checked_in_at: Time.zone.local(2026, 7, 15, 9, 0), created_at: Time.zone.local(2026, 7, 15, 10, 0))

      get hotel_front_desk_path(hotel), params: { tab: "in_house", view: "list" }

      expect(response.body.scan(/booking:(INHOUSE-ORDER-[A-Z]+)/).flatten).to eq([ later, earlier, oldest ].map(&:confirmation_token))
    end

    it "paginates in-house records at 25 per page" do
      26.times { |index| booking(status: "checked_in", confirmation_token: "INHOUSE-PAGE-#{index}", checked_in_at: index.minutes.ago) }

      get hotel_front_desk_path(hotel), params: { tab: "in_house", view: "list", in_house_page: 2 }

      expect(response.body).to include("page:2")
      expect(response.body.scan(/booking:INHOUSE-PAGE-/).size).to eq(1)
    end

    it "uses checkout search, ordering, and pagination" do
      older = booking(status: "completed", confirmation_token: "CHECKOUT-OLDER", checked_out_at: Time.current - 2.hours)
      newer = booking(status: "completed", confirmation_token: "CHECKOUT-NEWER", checked_out_at: Time.current - 1.hour)

      get hotel_front_desk_path(hotel), params: { tab: "checkout", checkout_query: "CHECKOUT" }

      expect(response.body.index(newer.confirmation_token)).to be < response.body.index(older.confirmation_token)
    end

    it "paginates checkout records at 25 per page" do
      26.times { |index| booking(status: "completed", confirmation_token: "CHECKOUT-PAGE-#{index}", checked_out_at: index.minutes.ago) }

      get hotel_front_desk_path(hotel), params: { tab: "checkout", view: "list", checkout_page: 2 }

      expect(response.body).to include("page:2")
      expect(response.body.scan(/booking:CHECKOUT-PAGE-/).size).to eq(1)
    end

    it "uses departure search, ordering, and pagination for pending checkouts" do
      later = booking(status: "checked_in", confirmation_token: "DEPARTURE-LATER", check_out: hotel_today + 1.day, created_at: 1.hour.ago)
      earlier = booking(status: "checked_in", confirmation_token: "DEPARTURE-EARLIER", check_out: hotel_today, created_at: 2.hours.ago)

      get hotel_front_desk_path(hotel), params: {
        tab: "departures", departure_query: "DEPARTURE", departure_start_date: hotel_today.iso8601, departure_end_date: (hotel_today + 1.day).iso8601
      }

      expect(response.body.index(earlier.confirmation_token)).to be < response.body.index(later.confirmation_token)
    end

    it "paginates departure records at 25 per page" do
      26.times { |index| booking(status: "checked_in", confirmation_token: "DEPARTURE-PAGE-#{index}", check_out: hotel_today) }

      get hotel_front_desk_path(hotel), params: { tab: "departures", view: "list", departure_page: 2 }

      expect(response.body).to include("page:2")
      expect(response.body.scan(/booking:DEPARTURE-PAGE-/).size).to eq(1)
    end

    it "keeps metrics unfiltered and renders same active-page records in both views" do
      stay = booking(status: "checked_in", confirmation_token: "VIEW-STAY", checked_in_at: Time.current)
      booking(status: "checked_in", confirmation_token: "OTHER-STAY", checked_in_at: Time.current)

      get hotel_front_desk_path(hotel), params: { tab: "in_house", in_house_query: "VIEW-STAY", view: "list" }
      expect(response.body).to include(stay.confirmation_token)
      expect(response.body).to include("metric:in_house:2")

      get hotel_front_desk_path(hotel), params: { tab: "in_house", in_house_query: "VIEW-STAY", view: "rooms" }
      expect(response.body).to include(stay.confirmation_token)
    end

    it "renders compact accessible room cards without guest contact details", :room_cards do
      grant_arrival_permission
      grant_booking_permission
      hotel.update!(time_zone: "Kuala Lumpur")
      created_at = Time.utc(2026, 7, 15, 18, 30)
      records = {
        bookings: booking(status: "confirmed", confirmation_token: "ROOM-BOOKING", guest_name: "AReallyLongGuestNameWithoutSpacesThatMustRemainFullyVisible", created_at:, adults: 2, children: 0),
        arrivals: booking(status: "confirmed", confirmation_token: "ROOM-ARRIVAL", guest_name: "AReallyLongGuestNameWithoutSpacesThatMustRemainFullyVisible", check_in: hotel_today, created_at:, adults: 2, children: 0),
        in_house: booking(status: "checked_in", confirmation_token: "ROOM-IN-HOUSE", guest_name: "AReallyLongGuestNameWithoutSpacesThatMustRemainFullyVisible", checked_in_at: Time.current, created_at:, adults: 2, children: 0),
        departures: booking(status: "checked_in", confirmation_token: "ROOM-DEPARTURE", guest_name: "AReallyLongGuestNameWithoutSpacesThatMustRemainFullyVisible", check_out: hotel_today, created_at:, adults: 2, children: 0),
        checkout: booking(status: "completed", confirmation_token: "ROOM-CHECKOUT", guest_name: "AReallyLongGuestNameWithoutSpacesThatMustRemainFullyVisible", checked_out_at: Time.current, created_at:, adults: 2, children: 0)
      }
      queries = {
        bookings: { booking_query: "ROOM-BOOKING" }, arrivals: { arrival_q: "ROOM-ARRIVAL" },
        in_house: { in_house_query: "ROOM-IN-HOUSE" }, departures: { departure_query: "ROOM-DEPARTURE" },
        checkout: { checkout_query: "ROOM-CHECKOUT" }
      }

      records.each do |tab, record|
        get hotel_front_desk_path(hotel), params: { tab:, view: "rooms", **queries.fetch(tab) }

        card = response.parsed_body.at_css("article.front-desk-stay-card")
        grid = card.parent
        expect(grid["class"]).to include("grid-cols-1", "md:grid-cols-2", "xl:grid-cols-4")
        expect(grid["class"]).not_to include("2xl:grid-cols-3")
        booking_date = card.css("dt").find { |label| label.text.strip == "Booking date" }
        expect(booking_date).to be_present
        expect(booking_date.at_xpath("following-sibling::dd")&.text&.strip).to eq(
          record.created_at.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y")
        )
        expect(card.at_css("[aria-label='2 Adults'] svg[aria-hidden='true']")).to be_present
        expect(card.at_css("[aria-label='0 Children'] svg[aria-hidden='true']")).to be_present
        expect(card.at_css("[aria-label='2 Adults'] span[aria-hidden='true']")&.text).to eq("2")
        expect(card.at_css("[aria-label='0 Children'] span[aria-hidden='true']")&.text).to eq("0")
        expect(card.text).not_to include(record.guest_email, record.guest_phone)
        expect(card.css("dt").map { |label| label.text.strip }).not_to include("Email", "Phone", "Contact")
        expect(card.css("dt").map { |label| label.text.strip }).to include("Total", "Paid", "Balance")
        expect(card.at_css("button[aria-label='Booking actions']")).to be_present
        expect(card.css("header > span > span").map { |line| line.text.strip }).to eq(%w[Unassigned Room])
        guest_name = card.at_xpath(".//p[normalize-space()='AReallyLongGuestNameWithoutSpacesThatMustRemainFullyVisible']")
        expect(guest_name["class"]).to include("break-words")
        expect(guest_name["class"]).not_to include("truncate")
      end
    end

    it "shows audit trail actions on all room-card tabs only when feature and permission allow", :room_cards do
      grant_arrival_permission
      grant_booking_permission
      plan = create(:plan)
      hotel.update!(plan: plan)
      feature = create(:feature, feature_group: create(:feature_group), slug: "full_audit_trail")
      plan_feature = create(:plan_feature, plan: plan, feature: feature, enabled: true)
      records = {
        bookings: booking(status: "confirmed", confirmation_token: "AUDIT-BOOKING"),
        arrivals: booking(status: "confirmed", confirmation_token: "AUDIT-ARRIVAL", check_in: hotel_today),
        in_house: booking(status: "checked_in", confirmation_token: "AUDIT-IN-HOUSE", checked_in_at: Time.current),
        departures: booking(status: "checked_in", confirmation_token: "AUDIT-DEPARTURE", check_out: hotel_today),
        checkout: booking(status: "completed", confirmation_token: "AUDIT-CHECKOUT", checked_out_at: Time.current)
      }
      queries = {
        bookings: { booking_query: "AUDIT-BOOKING" }, arrivals: { arrival_q: "AUDIT-ARRIVAL" },
        in_house: { in_house_query: "AUDIT-IN-HOUSE" }, departures: { departure_query: "AUDIT-DEPARTURE" },
        checkout: { checkout_query: "AUDIT-CHECKOUT" }
      }

      records.each do |tab, record|
        get hotel_front_desk_path(hotel), params: { tab:, view: "rooms", **queries.fetch(tab) }

        action = response.parsed_body.at_xpath("//a[normalize-space()='Audit trail']")
        expect(action).to be_present, "expected Audit trail on #{tab}"
        expect(action["href"]).to eq(hotel_booking_action_audit_trail_path(hotel, record))
        expect(action["data-turbo-frame"]).to eq("booking_action_sheet")
        menu = action.ancestors.find { |ancestor| ancestor["role"] == "menu" }
        expect(menu.css('[role="separator"]').size).to eq(1)
        group = action.ancestors.find { |ancestor| ancestor["role"] == "group" }
        expected_order = [ "label", "separator" ] + Array.new(menu.css('[role="menuitem"]').size, "menuitem")
        expect(group.element_children.map { |child| child["role"] || ("menuitem" if child.at_css('[role="menuitem"]')) || "label" }).to eq(
          expected_order
        )
      end

      plan_feature.update!(enabled: false)
      get hotel_front_desk_path(hotel), params: { tab: :bookings, view: "rooms", **queries.fetch(:bookings) }
      expect(response.parsed_body.at_xpath("//a[normalize-space()='Audit trail']")).to be_nil

      plan_feature.update!(enabled: true)
      role.permissions.delete(Permission.find_by!(slug: "view_bookings"))
      get hotel_front_desk_path(hotel), params: { tab: :bookings, view: "rooms", **queries.fetch(:bookings) }
      expect(response.parsed_body.at_xpath("//a[normalize-space()='Audit trail']")).to be_nil
    end

    it "keeps compact spacing between the search icon and text" do
      grant_booking_permission

      get hotel_front_desk_path(hotel), params: { tab: "bookings", view: "rooms" }

      search = response.parsed_body.at_css('input[aria-label="Search reservations"]')
      expect(search["class"]).to include("pl-7")
      expect(search["class"]).not_to include("pl-8", "pl-9")
    end

    it "renders accessible arrivals workspace controls and list actions" do
      grant_arrival_permission
      grant_booking_permission
      booking(status: "confirmed", confirmation_token: "ARRIVAL-WORKSPACE", check_in: hotel_today)
      arrival_start_date = hotel_today
      arrival_end_date = hotel_today + 1.day

      get hotel_front_desk_path(hotel), params: {
        tab: "arrivals", view: "list", arrival_q: "Aisha", in_house_query: "Stay",
        departure_query: "Departure", room_assignment: "unassigned", in_house_page: 2, departure_page: 3,
        arrival_start_date: arrival_start_date.iso8601, arrival_end_date: arrival_end_date.iso8601
      }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("h1")&.text&.strip).to eq("Reservations")
      expect(document.at_css("[data-front-desk-metrics]")).to be_present
      expect(document.css("[data-front-desk-metrics] a, [data-front-desk-metrics] button")).to be_empty
      expect(document.at_css("[aria-label='Reservation sections'] a[aria-current='page']")&.text).to include("Arrivals")
      view_group = document.at_css(".panel-button-group[aria-label='Reservation view']")
      expect(view_group).to be_present
      expect(view_group.at_css("a.panel-button[aria-current='page']")&.text).to include("List")
      expect(view_group.at_css("a[href*='view=rooms']")&.[]("href")).to include(
        "arrival_start_date=#{arrival_start_date.iso8601}", "arrival_end_date=#{arrival_end_date.iso8601}",
        "in_house_query=Stay", "departure_query=Departure", "in_house_page=2", "departure_page=3"
      )
      expect(document.at_css("#reservation-view.tabs-root")).to be_nil
      expect(document.at_css("input[name='arrival_q'][aria-label='Search reservations']")).to be_present
      range_root = document.at_css("[data-controller~='front-desk-date-range']")
      expect(range_root).to be_present
      expect(range_root.at_css("[data-front-desk-date-range-target='picker'] calendar-range[months='2']")).to be_present
      expect(range_root.at_css(".panel-form-field[data-size='lg']")).to be_present
      expect(range_root.at_css("input[name='front_desk_date_range']")&.[]("value")).to eq("#{arrival_start_date.iso8601}/#{arrival_end_date.iso8601}")
      expect(range_root.at_css("input[name='arrival_start_date'][data-front-desk-date-range-target='start']")&.[]("value")).to eq(arrival_start_date.iso8601)
      expect(range_root.at_css("input[name='arrival_end_date'][data-front-desk-date-range-target='end']")&.[]("value")).to eq(arrival_end_date.iso8601)
      expect(document.css(".panel-form-field").count { |field| field.text.include?("Start date") || field.text.include?("End date") }).to eq(0)
      expect(document.css("th").map(&:text).map(&:strip)).to include("Guest / Reference", "Pre-Checkin", "Guarantee", "Docs / Notes")
      expect(response.body).to include("Not Started")
      expect(response.body).to include("Check In")
      expect(response.body).not_to include("Room Status")
    end

    it "limits arrival date controls and list headers to arrivals" do
      get hotel_front_desk_path(hotel), params: { tab: "in_house", view: "list" }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("input[name='arrival_start_date'], input[name='arrival_end_date']")).to be_nil
      expect(document.at_css("[data-controller~='front-desk-date-range']")).to be_nil
      expect(document.at_css("input[name='front_desk_date_range']")).to be_nil
      expect(document.css("th").map(&:text).map(&:strip)).to include("Contact", "Stay Dates", "Checked In", "Rooms")
      expect(response.body).not_to include("Pre-Checkin")
    end

    it "keeps active page for view links and resets it only in active-tab filters" do
      grant_arrival_permission

      get hotel_front_desk_path(hotel), params: {
        tab: "arrivals", view: "list", arrival_date: hotel_today, arrival_q: "Aisha",
        arrival_page: 2, in_house_page: 3, departure_page: 4
      }

      document = Nokogiri::HTML(response.body)
      rooms_link = document.at_css("[aria-label='Reservation view'] a[href*='view=rooms']")
      expect(rooms_link["href"]).to include("arrival_page=2", "in_house_page=3", "departure_page=4")
      expect(document.at_css("[data-controller~='front-desk-date-range'] input[name='arrival_start_date']")).to be_present
      expect(document.at_css("[data-controller~='front-desk-date-range'] input[name='arrival_end_date']")).to be_present
      expect(document.at_css("form[action*='front-desk'] input[name='arrival_q']")).to be_present
      expect(document.css("form input[name='arrival_page']")).to be_empty
      expect(document.css("form input[name='in_house_page']").length).to be >= 1
    end

    it "uses system typography and preserves arrival mobile fields and permitted drawer actions" do
      grant_arrival_permission
      grant_booking_permission
      confirmed = booking(status: "confirmed", confirmation_token: "MOBILE-CONFIRMED", check_in: hotel_today)
      checked_in = booking(status: "checked_in", confirmation_token: "MOBILE-CHECKED-IN", check_in: hotel_today)

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", view: "list", arrival_q: "MOBILE" }

      document = Nokogiri::HTML(response.body)
      mobile = document.at_css("#front-desk-results section > .lg\\:hidden")
      expect(response.body).not_to include("font-serif")
      expect(mobile.text).to include("2 adults, 0 children", "Not Required", "No documents")
      check_in_link = mobile.css("a").find { |link| link.text.strip == "Check In" }
      expect(check_in_link["href"]).to include("return_to=")
      expect(check_in_link["data-offcanvas-variant"]).to eq("right")
      expect(mobile.text).to include("Checked in", "Edit Time")
      edit_time_link = mobile.css("a").find { |link| link.text.strip == "Edit Time" }
      expect(edit_time_link["href"]).to include(checked_in.id.to_s)
      expect(response.body).to include(confirmed.confirmation_token)
    end

    it "keeps mobile lifecycle drawer paths, variants, and checkout fields" do
      late = booking(status: "review_due_out", confirmation_token: "MOBILE-LATE", checked_in_at: Time.current)
      checkout = booking(status: "checkout_required", confirmation_token: "MOBILE-CHECKOUT", checked_in_at: Time.current)
      departed = booking(status: "completed", confirmation_token: "MOBILE-DEPARTED", checked_in_at: Time.current, checked_out_at: Time.current)

      get hotel_front_desk_path(hotel), params: { tab: "in_house", view: "list", in_house_query: "MOBILE" }
      mobile = Nokogiri::HTML(response.body).at_css("#front-desk-results section > .lg\\:hidden")
      late_link = mobile.css("a").find { |link| link.text.strip == "Review late checkout" }
      checkout_link = mobile.css("a").find { |link| link.text.strip == "Complete checkout" }
      expect(late_link["href"]).to include(late.id.to_s, "return_to=")
      expect(late_link["data-offcanvas-variant"]).to eq("right")
      expect(checkout_link["href"]).to include(checkout.id.to_s, "return_to=")
      expect(checkout_link["data-offcanvas-variant"]).to eq("fullscreen-bottom")

      get hotel_front_desk_path(hotel), params: { tab: "checkout", view: "list", checkout_query: "MOBILE" }
      mobile = Nokogiri::HTML(response.body).at_css("#front-desk-results section > .lg\\:hidden")
      expect(mobile.text).to include("Contact", "Stay Dates", "Checked In", "Checked Out", "Rooms", "View booking", departed.confirmation_token)
    end

    it "renders arrival and in-house identity markers in desktop and mobile records" do
      grant_arrival_permission
      arrival_guest = create(:guest, blacklisted: true, created_by_hotel: hotel)
      arrival = booking(status: "confirmed", confirmation_token: "MARKED-ARRIVAL", check_in: hotel_today, vip: true)
      create(:booking_guest, booking: arrival, guest: arrival_guest, is_primary: true)
      create(:booking_guest, booking: booking(status: "completed", confirmation_token: "MARKED-ARRIVAL-HISTORY", checked_out_at: 1.day.ago), guest: arrival_guest, is_primary: true)
      stay_guest = create(:guest, blacklisted: true, created_by_hotel: hotel)
      stay = booking(status: "checked_in", confirmation_token: "MARKED-STAY", checked_in_at: Time.current, vip: true)
      create(:booking_guest, booking: stay, guest: stay_guest, is_primary: true)
      create(:booking_guest, booking: booking(status: "completed", confirmation_token: "MARKED-STAY-HISTORY", checked_out_at: 1.day.ago), guest: stay_guest, is_primary: true)

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", view: "list", arrival_q: "MARKED" }
      document = Nokogiri::HTML(response.body)
      expect(document.text).to include(arrival.confirmation_token, "VIP", "Blacklisted", "Repeat guest")
      expect(document.at_css("#front-desk-results .lg\\:hidden").text).to include("VIP", "Blacklisted", "Repeat guest")

      get hotel_front_desk_path(hotel), params: { tab: "in_house", view: "list", in_house_query: "MARKED" }
      document = Nokogiri::HTML(response.body)
      expect(document.text).to include(stay.confirmation_token, "VIP", "Blacklisted", "Repeat guest")
      expect(document.at_css("#front-desk-results .lg\\:hidden").text).to include("VIP", "Blacklisted", "Repeat guest")
    end

    it "renders tab-specific empty states and semantic row headers" do
      grant_arrival_permission

      get hotel_front_desk_path(hotel), params: { tab: "arrivals" }
      document = Nokogiri::HTML(response.body)
      expect(document.text).to include("No arrivals scheduled for this date.")

      get hotel_front_desk_path(hotel), params: { tab: "in_house" }
      document = Nokogiri::HTML(response.body)
      expect(document.text).to include("No guests are currently checked in.")

      get hotel_front_desk_path(hotel), params: { tab: "departures" }
      document = Nokogiri::HTML(response.body)
      expect(document.text).to include("No guests are due to check out today.")

      get hotel_front_desk_path(hotel), params: { tab: "checkout" }
      document = Nokogiri::HTML(response.body)
      expect(document.text).to include("No guests have checked out today.")

      grant_arrival_permission
      booking(status: "confirmed", confirmation_token: "ROW-ARRIVAL", check_in: hotel_today)
      booking(status: "checked_in", confirmation_token: "ROW-STAY", checked_in_at: Time.current)
      booking(status: "checked_in", confirmation_token: "ROW-DEPARTURE", check_out: hotel_today)
      booking(status: "completed", confirmation_token: "ROW-CHECKOUT", checked_out_at: Time.current)

      %w[arrivals in_house departures checkout].each do |tab|
        get hotel_front_desk_path(hotel), params: { tab:, view: "list" }
        expect(Nokogiri::HTML(response.body).at_css("#front-desk-results .lg\\:block tbody th[scope='row']")).to be_present
      end
    end

    it "renders checked out text status in mobile checkout" do
      booking(status: "completed", confirmation_token: "STATUS-CHECKOUT", checked_out_at: Time.current)

      get hotel_front_desk_path(hotel), params: { tab: "checkout", view: "list", checkout_query: "STATUS" }

      expect(Nokogiri::HTML(response.body).at_css("#front-desk-results .lg\\:hidden").text).to include("Checked out")
    end

    it "renders desktop and mobile in-house lifecycle status badges" do
      booking(status: "review_due_out", confirmation_token: "STATUS-LATE", checked_in_at: Time.current)
      booking(status: "checkout_required", confirmation_token: "STATUS-CHECKOUT", checked_in_at: Time.current)

      get hotel_front_desk_path(hotel), params: { tab: "in_house", view: "list", in_house_query: "STATUS" }

      document = Nokogiri::HTML(response.body)
      desktop = document.at_css("#front-desk-results .lg\\:block")
      mobile = document.at_css("#front-desk-results .lg\\:hidden")
      expect(desktop.at_css(".bg-warning\\/10")&.text&.strip).to eq("Late")
      expect(desktop.at_css(".bg-destructive\\/10")&.text&.strip).to eq("Checkout required")
      expect(mobile.at_css(".bg-warning\\/10")&.text&.strip).to eq("Late Checkout")
      expect(mobile.at_css(".bg-destructive\\/10")&.text&.strip).to eq("Checkout Required")
    end

    it "renders presenter pre-checkin badges in desktop and mobile arrivals" do
      grant_arrival_permission
      booking(status: "confirmed", confirmation_token: "PRECHECK-COMPLETE", check_in: hotel_today, pre_checkin_status: "completed")
      booking(status: "confirmed", confirmation_token: "PRECHECK-PENDING", check_in: hotel_today, pre_checkin_status: "pending")
      booking(status: "confirmed", confirmation_token: "PRECHECK-FAILED", check_in: hotel_today, pre_checkin_status: "failed")

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", view: "list", arrival_q: "PRECHECK" }

      document = Nokogiri::HTML(response.body)
      desktop = document.at_css("#front-desk-results .lg\\:block")
      mobile = document.at_css("#front-desk-results .lg\\:hidden")
      expect(desktop.at_css(".border-success\\/30")&.text&.strip).to eq("Completed")
      expect(desktop.at_css(".border-warning\\/30")&.text&.strip).to eq("Pending")
      expect(desktop.at_css(".border-destructive\\/30")&.text&.strip).to eq("Failed")
      expect(mobile.at_css(".border-success\\/30")&.text&.strip).to eq("Completed")
      expect(mobile.at_css(".border-warning\\/30")&.text&.strip).to eq("Pending")
      expect(mobile.at_css(".border-destructive\\/30")&.text&.strip).to eq("Failed")
    end
  end

  describe "legacy redirects" do
    it "maps only supported arrivals parameters before authorization" do
      get hotel_arrivals_path(hotel), params: { date: "2026-07-15", q: "Aisha", page: 2, ignored: "x" }

      expect(response).to redirect_to(hotel_front_desk_path(hotel, tab: "arrivals", view: "list", arrival_date: "2026-07-15", arrival_q: "Aisha", arrival_page: 2))
      expect(response).to have_http_status(:moved_permanently)
    end

    it "maps only supported in-house parameters" do
      get hotel_in_house_guests_path(hotel), params: { query: "Aisha", room_assignment: "assigned", page: 2, ignored: "x" }

      expect(response).to redirect_to(hotel_front_desk_path(hotel, tab: "in_house", view: "list", in_house_query: "Aisha", room_assignment: "assigned", in_house_page: 2))
      expect(response).to have_http_status(:moved_permanently)
    end

    it "maps only supported checkout parameters" do
      get hotel_checked_out_guests_path(hotel), params: { query: "Aisha", page: 2, ignored: "x" }

      expect(response).to redirect_to(hotel_front_desk_path(hotel, tab: "checkout", view: "list", checkout_query: "Aisha", checkout_page: 2))
      expect(response).to have_http_status(:moved_permanently)
    end
  end
end
