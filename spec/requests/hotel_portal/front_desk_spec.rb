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

  describe "GET /hotel/:hotel_id/front-desk" do
    it "redirects unauthenticated users to login" do
      delete logout_path

      get hotel_front_desk_path(hotel)

      expect(response).to redirect_to(login_path)
    end

    def grant_booking_permission
      permission = Permission.find_or_create_by!(slug: "manage_bookings") { |record| record.name = "Manage Bookings" }
      role.permissions << permission
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
      arrival = booking(status: "confirmed", confirmation_token: "RESTRICTED-ARRIVAL", check_in: Date.current)
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
      arrival = booking(status: "confirmed", confirmation_token: "GLOBAL-ONLY-ARRIVAL", check_in: Date.current)

      get hotel_front_desk_path(hotel), params: { tab: "arrivals" }

      expect(response.body).to include("active-tab:in_house")
      expect(response.body).not_to include("metric:arrivals")
      expect(response.body).not_to include(arrival.confirmation_token)
    end

    it "makes in-house and departures available without arrival permission" do
      get hotel_front_desk_path(hotel), params: { tab: "departures" }

      expect(response.body).to include("active-tab:departures")
      expect(response.body).to include("tab:in_house")
    end

    it "normalizes invalid state safely" do
      get hotel_front_desk_path(hotel), params: {
        tab: "invalid", view: "invalid", arrival_date: "nope", room_assignment: "invalid",
        in_house_page: "-3", arrival_page: "x", departure_page: "0"
      }

      expect(response.body).to include("active-tab:in_house")
      expect(response.body).to include("active-view:list")
      expect(response.body).to include("page:1")
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
      expect(response.body).to include("active-view:list")
      expect(response.body).to include("page:1")
    end

    it "uses arrivals search, ordering, and 25-row pagination" do
      grant_arrival_permission
      matching = booking(status: "confirmed", confirmation_token: "ARRIVAL-MATCH", check_in: Date.current, created_at: 2.days.ago)
      excluded = booking(status: "confirmed", confirmation_token: "ARRIVAL-EXCLUDED", check_in: Date.current)
      25.times { |index| booking(status: "confirmed", confirmation_token: "ARRIVAL-#{index}", check_in: Date.current) }

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", arrival_q: "MATCH", arrival_page: 1 }
      expect(response.body).to include(matching.confirmation_token)
      expect(response.body).not_to include(excluded.confirmation_token)

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", arrival_page: 2 }
      expect(response.body).not_to include(matching.confirmation_token)
      expect(response.body).to include("ARRIVAL-24")
    end

    it "orders arrivals by created_at ascending with a 25-record page boundary" do
      grant_arrival_permission
      27.times do |index|
        booking(
          status: "confirmed",
          confirmation_token: format("ARRIVAL-ORDER-%02d", index),
          check_in: Date.current,
          created_at: Time.zone.local(2026, 7, 15, 9, 0) + index.minutes
        )
      end

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", arrival_page: 1 }

      page_one = response.body.scan(/booking:(ARRIVAL-ORDER-\d+)/).flatten
      expect(page_one).to eq((0...25).map { |index| format("ARRIVAL-ORDER-%02d", index) })

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", arrival_page: 2 }

      expect(response.body.scan(/booking:(ARRIVAL-ORDER-\d+)/).flatten).to eq(%w[ARRIVAL-ORDER-25 ARRIVAL-ORDER-26])
    end

    it "keeps equal-created arrivals on stable id-ordered pages" do
      grant_arrival_permission
      timestamp = Time.zone.local(2026, 7, 15, 9, 0)
      27.times do |index|
        booking(
          status: "confirmed",
          confirmation_token: format("ARRIVAL-TIE-%02d", index),
          check_in: Date.current,
          created_at: timestamp
        )
      end

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", arrival_page: 1 }
      expect(response.body.scan(/booking:(ARRIVAL-TIE-\d+)/).flatten).to eq((0...25).map { |index| format("ARRIVAL-TIE-%02d", index) })

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", arrival_page: 2 }
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

      get hotel_front_desk_path(hotel), params: { tab: "in_house" }

      expect(response.body.scan(/booking:(INHOUSE-ORDER-[A-Z]+)/).flatten).to eq([ later, earlier, oldest ].map(&:confirmation_token))
    end

    it "paginates in-house records at 25 per page" do
      26.times { |index| booking(status: "checked_in", confirmation_token: "INHOUSE-PAGE-#{index}", checked_in_at: index.minutes.ago) }

      get hotel_front_desk_path(hotel), params: { tab: "in_house", in_house_page: 2 }

      expect(response.body).to include("page:2")
      expect(response.body.scan(/booking:INHOUSE-PAGE-/).size).to eq(1)
    end

    it "uses departure search, ordering, and pagination" do
      older = booking(status: "completed", confirmation_token: "DEPARTURE-OLDER", checked_out_at: Time.current - 2.hours)
      newer = booking(status: "completed", confirmation_token: "DEPARTURE-NEWER", checked_out_at: Time.current - 1.hour)

      get hotel_front_desk_path(hotel), params: { tab: "departures", departure_query: "DEPARTURE" }

      expect(response.body.index(newer.confirmation_token)).to be < response.body.index(older.confirmation_token)
    end

    it "paginates departure records at 25 per page" do
      26.times { |index| booking(status: "completed", confirmation_token: "DEPARTURE-PAGE-#{index}", checked_out_at: index.minutes.ago) }

      get hotel_front_desk_path(hotel), params: { tab: "departures", departure_page: 2 }

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

    it "renders accessible arrivals workspace controls and list actions" do
      grant_arrival_permission
      grant_booking_permission
      booking(status: "confirmed", confirmation_token: "ARRIVAL-WORKSPACE", check_in: Date.current)

      get hotel_front_desk_path(hotel), params: {
        tab: "arrivals", view: "list", arrival_q: "Aisha", in_house_query: "Stay",
        departure_query: "Departure", room_assignment: "unassigned", in_house_page: 2, departure_page: 3
      }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("h1")&.text&.strip).to eq("Reservations")
      expect(document.at_css("[data-front-desk-metrics]")).to be_present
      expect(document.css("[data-front-desk-metrics] a, [data-front-desk-metrics] button")).to be_empty
      expect(document.at_css("[aria-label='Reservation sections'] a[aria-current='page']")&.text).to include("Arrivals")
      expect(document.at_css("[aria-label='Reservation view'] a[href*='view=rooms']")&.[]("href")).to include("in_house_query=Stay", "departure_query=Departure", "in_house_page=2", "departure_page=3")
      expect(document.at_css("input[name='start_date']")).to be_present
      expect(document.css("th").map(&:text).map(&:strip)).to include("Guest / Reference", "Pre-Checkin", "Guarantee", "Docs / Notes")
      expect(response.body).to include("Not Started")
      expect(response.body).to include("Check In")
      expect(response.body).not_to include("Room Status")
    end

    it "limits arrival date controls and list headers to arrivals" do
      get hotel_front_desk_path(hotel), params: { tab: "in_house" }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("input[name='arrival_date']")).to be_nil
      expect(document.css("th").map(&:text).map(&:strip)).to include("Contact", "Stay Dates", "Checked In", "Rooms")
      expect(response.body).not_to include("Pre-Checkin")
    end

    it "keeps active page for view links and resets it only in active-tab filters" do
      grant_arrival_permission

      get hotel_front_desk_path(hotel), params: {
        tab: "arrivals", view: "list", arrival_date: Date.current, arrival_q: "Aisha",
        arrival_page: 2, in_house_page: 3, departure_page: 4
      }

      document = Nokogiri::HTML(response.body)
      rooms_link = document.at_css("[aria-label='Reservation view'] a[href*='view=rooms']")
      expect(rooms_link["href"]).to include("arrival_page=2", "in_house_page=3", "departure_page=4")
      today_button = document.at_css("button[data-action*='front-desk-date-range#selectToday']")
      expect(today_button&.text&.strip).to eq("Today")
      expect(document.at_css("form[action*='front-desk'] input[name='arrival_q']")).to be_present
      expect(document.css("form input[name='arrival_page']")).to be_empty
      expect(document.css("form input[name='in_house_page']").length).to be >= 1
    end

    it "uses system typography and preserves arrival mobile fields and permitted drawer actions" do
      grant_arrival_permission
      grant_booking_permission
      confirmed = booking(status: "confirmed", confirmation_token: "MOBILE-CONFIRMED", check_in: Date.current)
      checked_in = booking(status: "checked_in", confirmation_token: "MOBILE-CHECKED-IN", check_in: Date.current)

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", arrival_q: "MOBILE" }

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

    it "keeps mobile lifecycle drawer paths, variants, and departure fields" do
      late = booking(status: "review_due_out", confirmation_token: "MOBILE-LATE", checked_in_at: Time.current)
      checkout = booking(status: "checkout_required", confirmation_token: "MOBILE-CHECKOUT", checked_in_at: Time.current)
      departed = booking(status: "completed", confirmation_token: "MOBILE-DEPARTED", checked_in_at: Time.current, checked_out_at: Time.current)

      get hotel_front_desk_path(hotel), params: { tab: "in_house", in_house_query: "MOBILE" }
      mobile = Nokogiri::HTML(response.body).at_css("#front-desk-results section > .lg\\:hidden")
      late_link = mobile.css("a").find { |link| link.text.strip == "Review late checkout" }
      checkout_link = mobile.css("a").find { |link| link.text.strip == "Complete checkout" }
      expect(late_link["href"]).to include(late.id.to_s, "return_to=")
      expect(late_link["data-offcanvas-variant"]).to eq("right")
      expect(checkout_link["href"]).to include(checkout.id.to_s, "return_to=")
      expect(checkout_link["data-offcanvas-variant"]).to eq("fullscreen-bottom")

      get hotel_front_desk_path(hotel), params: { tab: "departures", departure_query: "MOBILE" }
      mobile = Nokogiri::HTML(response.body).at_css("#front-desk-results section > .lg\\:hidden")
      expect(mobile.text).to include("Contact", "Stay Dates", "Checked In", "Checked Out", "Rooms", "View booking", departed.confirmation_token)
    end

    it "renders arrival and in-house identity markers in desktop and mobile records" do
      grant_arrival_permission
      arrival_guest = create(:guest, blacklisted: true, created_by_hotel: hotel)
      arrival = booking(status: "confirmed", confirmation_token: "MARKED-ARRIVAL", check_in: Date.current, vip: true)
      create(:booking_guest, booking: arrival, guest: arrival_guest, is_primary: true)
      create(:booking_guest, booking: booking(status: "completed", confirmation_token: "MARKED-ARRIVAL-HISTORY", checked_out_at: 1.day.ago), guest: arrival_guest, is_primary: true)
      stay_guest = create(:guest, blacklisted: true, created_by_hotel: hotel)
      stay = booking(status: "checked_in", confirmation_token: "MARKED-STAY", checked_in_at: Time.current, vip: true)
      create(:booking_guest, booking: stay, guest: stay_guest, is_primary: true)
      create(:booking_guest, booking: booking(status: "completed", confirmation_token: "MARKED-STAY-HISTORY", checked_out_at: 1.day.ago), guest: stay_guest, is_primary: true)

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", arrival_q: "MARKED" }
      document = Nokogiri::HTML(response.body)
      expect(document.text).to include(arrival.confirmation_token, "VIP", "Blacklisted", "Repeat guest")
      expect(document.at_css("#front-desk-results .lg\\:hidden").text).to include("VIP", "Blacklisted", "Repeat guest")

      get hotel_front_desk_path(hotel), params: { tab: "in_house", in_house_query: "MARKED" }
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
      expect(document.text).to include("No guests have checked out today.")

      grant_arrival_permission
      booking(status: "confirmed", confirmation_token: "ROW-ARRIVAL", check_in: Date.current)
      booking(status: "checked_in", confirmation_token: "ROW-STAY", checked_in_at: Time.current)
      booking(status: "completed", confirmation_token: "ROW-DEPARTURE", checked_out_at: Time.current)

      %w[arrivals in_house departures].each do |tab|
        get hotel_front_desk_path(hotel), params: { tab: }
        expect(Nokogiri::HTML(response.body).at_css("#front-desk-results .lg\\:block tbody th[scope='row']")).to be_present
      end
    end

    it "renders checked out text status in mobile departures" do
      booking(status: "completed", confirmation_token: "STATUS-DEPARTURE", checked_out_at: Time.current)

      get hotel_front_desk_path(hotel), params: { tab: "departures", departure_query: "STATUS" }

      expect(Nokogiri::HTML(response.body).at_css("#front-desk-results .lg\\:hidden").text).to include("Checked out")
    end

    it "renders desktop and mobile in-house lifecycle status badges" do
      booking(status: "review_due_out", confirmation_token: "STATUS-LATE", checked_in_at: Time.current)
      booking(status: "checkout_required", confirmation_token: "STATUS-CHECKOUT", checked_in_at: Time.current)

      get hotel_front_desk_path(hotel), params: { tab: "in_house", in_house_query: "STATUS" }

      document = Nokogiri::HTML(response.body)
      desktop = document.at_css("#front-desk-results .lg\\:block")
      mobile = document.at_css("#front-desk-results .lg\\:hidden")
      expect(desktop.at_css(".bg-amber-100")&.text&.strip).to eq("Late")
      expect(desktop.at_css(".bg-rose-100")&.text&.strip).to eq("Checkout required")
      expect(mobile.at_css(".bg-amber-50")&.text&.strip).to eq("Late Checkout")
      expect(mobile.at_css(".bg-rose-50")&.text&.strip).to eq("Checkout Required")
    end

    it "renders presenter pre-checkin badges in desktop and mobile arrivals" do
      grant_arrival_permission
      booking(status: "confirmed", confirmation_token: "PRECHECK-COMPLETE", check_in: Date.current, pre_checkin_status: "completed")
      booking(status: "confirmed", confirmation_token: "PRECHECK-PENDING", check_in: Date.current, pre_checkin_status: "pending")
      booking(status: "confirmed", confirmation_token: "PRECHECK-FAILED", check_in: Date.current, pre_checkin_status: "failed")

      get hotel_front_desk_path(hotel), params: { tab: "arrivals", arrival_q: "PRECHECK" }

      document = Nokogiri::HTML(response.body)
      desktop = document.at_css("#front-desk-results .lg\\:block")
      mobile = document.at_css("#front-desk-results .lg\\:hidden")
      expect(desktop.at_css(".border-emerald-200")&.text&.strip).to eq("Completed")
      expect(desktop.at_css(".border-amber-200")&.text&.strip).to eq("Pending")
      expect(desktop.at_css(".border-red-200")&.text&.strip).to eq("Failed")
      expect(mobile.at_css(".border-emerald-200")&.text&.strip).to eq("Completed")
      expect(mobile.at_css(".border-amber-200")&.text&.strip).to eq("Pending")
      expect(mobile.at_css(".border-red-200")&.text&.strip).to eq("Failed")
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

    it "maps only supported departure parameters" do
      get hotel_checked_out_guests_path(hotel), params: { query: "Aisha", page: 2, ignored: "x" }

      expect(response).to redirect_to(hotel_front_desk_path(hotel, tab: "departures", view: "list", departure_query: "Aisha", departure_page: 2))
      expect(response).to have_http_status(:moved_permanently)
    end
  end
end
