# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal Stay View", type: :request do
  around { |example| travel_to(Time.zone.local(2026, 7, 16, 10, 0, 0)) { example.run } }

  let(:hotel) { create(:hotel, accounting_business_date: Date.current) }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:room_type) { create(:room_type, hotel:, room_number_mode: "custom", room_numbers: %w[101 102]) }

  def grant(slug)
    permission = Permission.find_by(slug:) || create(:permission, slug:, name: slug.humanize)
    create(:role_permission, role:, permission:)
  end

  def turbo_headers
    { "Accept" => Mime[:turbo_stream].to_s, "Turbo-Frame" => "offcanvas_drawer" }
  end

  def enable_housekeeping_feature
    plan = create(:plan)
    hotel.update!(plan:)
    feature = create(:feature, slug: "task_assignment_minibar_log")
    create(:plan_feature, plan:, feature:, enabled: true)
    hotel.remove_instance_variable(:@plan_feature_map) if hotel.instance_variable_defined?(:@plan_feature_map)
  end

  before do
    grant("view_bookings")
    grant("manage_bookings")
    grant("manage_guest_arrival")
    grant("manage_room_status")
    create(:user_hotel_access, user:, hotel:, role:)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/stay-view" do
    it "requires authentication" do
      delete logout_path

      get hotel_stay_view_path(hotel)

      expect(response).to redirect_to(login_path)
    end

    it "renders the timeline board with canonical frame state" do
      booking = create(:booking, hotel:, guest_name: "Ada Lovelace", check_in: Date.current, check_out: Date.current + 2.days)
      create(:booking_room, booking:, room_type:, room_number: "101")

      get hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7, density: "comfortable")

      expect(response).to have_http_status(:success)
      expect(response.body).to match(/<turbo-frame[^>]+id="stay_view_board"/)
      expect(response.body).to include("stay-view-timeline", "Ada Lovelace")
      expect(response.body).to include('data-density="compact"')
      expect(response.body).not_to include('id="density-select-menu"')
      expect(response.body).to include('tabs-root--pill', 'data-controller="stay-view--filters"')
      expect(response.body).to include('id="start_date-date-picker"', 'id="days-select-menu"')
      expect(response.body).to include("All room types", "All booking statuses", "All occupancy states", "All physical statuses")
      expect(response.body).to include("Confirmed")

      document = Nokogiri::HTML(response.body)
      global_actions = document.at_css("[data-slot='stay-view-global-actions']")
      expect(global_actions.ancestors("#stay_view_toolbar")).to be_present
      expect(global_actions.at_css("a[href^='#{hotel_booking_transaction_walk_in_check_in_path(hotel)}']").text.squish).to eq("Walk-in")
      expect(global_actions.at_css("a[href^='#{hotel_booking_transaction_new_booking_path(hotel)}']").text.squish).to eq("Add booking")
      operational_counts = document.css("[data-slot='stay-view-operational-count']")
      expect(operational_counts.map { |badge| badge["data-state"] }).to eq(
        %w[all vacant occupied reserved blocked due_out dirty]
      )
      expect(operational_counts.map { |badge| badge.css("span").map(&:text) }).to eq(
        [ [ "All", "2" ], [ "Vacant", "1" ], [ "Occupied", "0" ], [ "Reserved", "1" ],
         [ "Blocked", "0" ], [ "Due out", "0" ], [ "Dirty", "0" ] ]
      )
      expect(document.at_css("button[aria-label='Stay View status guide']")).to be_present
      expect(document.at_css("#stay-view-status-guide-panel").text).to include("No-show review", "Do not disturb")
      expect(document.at_css("#stay-view-status-guide-panel").text).not_to include("Financial attention", "Direct Bill")
      badges = document.css("[data-slot='stay-view-inventory-badge']")
      expect(badges.size).to eq(7)
      expect(badges.first.text).to eq("1")
      expect(badges.first["aria-label"]).to eq(
        "1 available room for #{room_type.name} on #{I18n.l(Date.current, format: :long)}"
      )
      expect(badges[2].text).to eq("2")
      expect(document.css("[data-slot='stay-view-standard-rate']")).to be_empty
      expect(response.body).not_to include(room_type.base_price.to_s, "Standard nightly rate")
      footer_rows = document.css("[data-slot='timeline-footer-row']")
      expect(footer_rows.size).to eq(2)
      expect(footer_rows.map { |row| row.at_css(".panel-timeline__footer-label").text }).to eq(
        [ "Available inventory", "Occupancy" ]
      )
      expect(footer_rows.map { |row| row["role"] }).to eq([ "row", "row" ])
      expect(document.css("[data-slot='stay-view-footer-available']").map(&:text)).to eq([ "1", "1", "2", "2", "2", "2", "2" ])
      expect(document.css("[data-slot='stay-view-footer-occupancy']").map(&:text)).to eq([ "50%", "50%", "0%", "0%", "0%", "0%", "0%" ])
    end

    it "renders date-aware action menus for every available Timeline cell" do
      room_type
      start_date = Date.current - 1.day

      get hotel_stay_view_path(hotel, view: "timeline", start_date:, days: 7)

      document = Nokogiri::HTML(response.body)
      room_id = "stay_view_room_#{room_type.id}_101"
      past_menu = document.at_css("##{room_id}-#{start_date.iso8601}-cell-actions-menu")
      today_menu = document.at_css("##{room_id}-#{Date.current.iso8601}-cell-actions-menu")
      future_menu = document.at_css("##{room_id}-#{(Date.current + 1.day).iso8601}-cell-actions-menu")

      expect(past_menu.css("[role='menuitem']").map { |item| item.text.squish }).to eq(
        [ "Backdated check-in", "Maintenance block" ]
      )
      expect(today_menu.css("[role='menuitem']").map { |item| item.text.squish }).to eq(
        [ "Walk-in check-in", "Add booking", "Maintenance block" ]
      )
      expect(future_menu.css("[role='menuitem']").map { |item| item.text.squish }).to eq(
        [ "Add booking", "Maintenance block" ]
      )

      add_booking = today_menu.css("[role='menuitem']").find { |item| item.text.squish == "Add booking" }
      add_booking_uri = URI.parse(add_booking["href"])
      expect(add_booking_uri.path).to eq(hotel_booking_transaction_new_booking_path(hotel))
      expect(Rack::Utils.parse_nested_query(add_booking_uri.query)).to include(
        "check_in" => Date.current.iso8601,
        "check_out" => (Date.current + 1.day).iso8601,
        "room_type_id" => room_type.id.to_s,
        "room_number" => "101",
        "source" => "stay_view"
      )
      expect(add_booking["data-turbo-frame"]).to eq("offcanvas_drawer")

      today_trigger = document.at_css("##{room_id}-#{Date.current.iso8601}-cell-actions-trigger")
      expect(today_trigger["data-alignment"]).to eq("center")
    end

    it "keeps a checkout-only cell actionable and counts a due-out room at the left edge" do
      departing = create(
        :booking,
        hotel:,
        status: "review_due_out",
        check_in: Date.current - 1.day,
        check_out: Date.current,
        guest_name: "Departing Guest"
      )
      create(:booking_room, booking: departing, room_type:, room_number: "101")

      get hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7)

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("#stay_view_room_#{room_type.id}_101-#{Date.current.iso8601}-cell-actions")).to be_present
      checkout_trigger = document.at_css("#stay_view_room_#{room_type.id}_101-#{Date.current.iso8601}-cell-actions-trigger")
      expect(checkout_trigger["data-alignment"]).to eq("end")
      expect(document.at_css("[data-state='due_out']").css("span").map(&:text)).to eq([ "Due out", "1" ])
      expect(document.at_css("[data-state='vacant']").css("span").map(&:text)).to eq([ "Vacant", "1" ])
    end

    it "omits cell action triggers for sold and blocked dates" do
      booking = create(:booking, hotel:, check_in: Date.current, check_out: Date.current + 1.day)
      create(:booking_room, booking:, room_type:, room_number: "101")
      create(
        :room_block,
        hotel:,
        room_type:,
        room_number: "102",
        start_date: Date.current,
        end_date: Date.current
      )

      get hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7)

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("#stay_view_room_#{room_type.id}_101-#{Date.current.iso8601}-cell-actions")).to be_nil
      expect(document.at_css("#stay_view_room_#{room_type.id}_102-#{Date.current.iso8601}-cell-actions")).to be_nil
    end

    it "renders all operational count badges as zero when filters remove every room" do
      room_type

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current, physical_status: "dirty")

      document = Nokogiri::HTML(response.body)
      expect(document.css("[data-slot='stay-view-operational-count']").map { |badge| badge.css("span").map(&:text) }).to eq(
        [ [ "All", "0" ], [ "Vacant", "0" ], [ "Occupied", "0" ], [ "Reserved", "0" ],
         [ "Blocked", "0" ], [ "Due out", "0" ], [ "Dirty", "0" ] ]
      )
    end

    it "renders checkout-day availability after active blocks reduce footer capacity" do
      departing = create(
        :booking,
        hotel:,
        check_in: Date.current - 1.day,
        check_out: Date.current,
        guest_name: "Departing Guest"
      )
      create(:booking_room, booking: departing, room_type:, room_number: "101")
      create(
        :room_block,
        hotel:,
        room_type:,
        room_number: "102",
        start_date: Date.current,
        end_date: Date.current
      )

      get hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7)

      document = Nokogiri::HTML(response.body)
      available = document.css("[data-slot='stay-view-footer-available']").first
      occupancy = document.css("[data-slot='stay-view-footer-occupancy']").first
      expect(response).to have_http_status(:success)
      expect(available.text).to eq("1")
      expect(available["aria-label"]).to eq("1 available room on #{I18n.l(Date.current, format: :long)}")
      expect(occupancy.text).to eq("0%")
      expect(occupancy["aria-label"]).to eq("0 percent occupied on #{I18n.l(Date.current, format: :long)}")
    end

    it "renders master-plan dated rates and base-price fallbacks with rate permission" do
      grant("manage_rates")
      master_plan = room_type.rate_plans.order(:id).first
      create(:room_rate, room_type:, rate_plan: master_plan, date: Date.current, price: 145, currency: master_plan.currency)

      get hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7)

      document = Nokogiri::HTML(response.body)
      rates = document.css("[data-slot='stay-view-standard-rate']")
      expect(response).to have_http_status(:success)
      expect(rates.size).to eq(7)
      expect(rates.first.text).to eq("145.00")
      expect(rates.first["aria-label"]).to end_with("145.00 #{master_plan.currency}")
      expect(rates[1].text).to eq(CurrencyFormatter.format(room_type.base_price, currency: master_plan.currency, symbol: false))
    end

    it "renders N/A for an authorized genuinely missing standard rate" do
      grant("manage_rates")
      room_type.update_column(:base_price, nil)

      get hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7)

      expect(response).to have_http_status(:success)
      expect(Nokogiri::HTML(response.body).css("[data-slot='stay-view-standard-rate']").map(&:text)).to eq([ "N/A" ] * 7)
    end

    it "renders Room View from the shared projection" do
      room_type

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-testid="stay-view-room-cards"', "Room 101", "Room 102")
      expect(response.body).not_to include("stay-view-timeline")
    end

    it "groups Room View by room type by default and flattens it on request" do
      create(:room_type, hotel:, name: "Suite", room_numbers: [ "201" ])
      room_type

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)
      grouped = Nokogiri::HTML(response.body)
      expect(grouped.css("[data-testid='stay-view-room-cards'] section")).not_to be_empty

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current, group_by: "none")
      flat = Nokogiri::HTML(response.body)
      expect(flat.css("[data-testid='stay-view-room-cards'] section")).to be_empty
      expect(flat.css("[data-testid='stay-view-room-cards'] article h3").map(&:text)).to contain_exactly("101", "102", "201")
      expect(response.body).to include("Room 101", "Room 201")
    end

    it "renders authorized financial attention in Timeline View and a full badge in Room View" do
      grant("view_financial_status")
      booking = create(:booking, hotel:, guest_name: "Financial Guest", check_in: Date.current, check_out: Date.current + 2.days)
      create(:booking_room, booking:, room_type:, room_number: "101")
      folio = create(:booking_folio, booking:, hotel:)
      create(:booking_guest, booking:, guest: create(:guest, name: "Financial Guest"), is_primary: true)
      create(:folio_transaction, booking_folio: folio, amount: 240)

      get hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7)

      timeline = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:success)
      expect(timeline.at_css("[data-slot='stay-view-financial-attention']")["aria-label"]).to eq(
        "Guest: Financial Guest · Balance due · MYR 240.00"
      )
      expect(response.body).to include("Guest: Financial Guest · Balance due · MYR 240.00")

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)

      room_view = Nokogiri::HTML(response.body)
      badge = room_view.at_css("[data-slot='stay-view-financial-signal']")
      expect(badge.text).to eq("Guest: Financial Guest · Balance due · MYR 240.00")
      expect(badge["data-variant"]).to eq("warning")
    end

    it "renders valid Direct Bill as information without a Timeline warning" do
      grant("view_financial_status")
      booking = create(:booking, hotel:, guest_name: "Corporate Guest", check_in: Date.current, check_out: Date.current + 2.days)
      create(:booking_room, booking:, room_type:, room_number: "101")
      relationship = create(
        :hotel_corporate_account,
        hotel:,
        corporate_account: create(:account, :corporate, name: "Acme Sdn Bhd"),
        direct_bill_enabled: true
      )
      party = create(:booking_billing_party, booking:, hotel:, hotel_corporate_account: relationship)
      create(
        :booking_billing_terms,
        booking_billing_party: party,
        settlement_type: "city_ledger",
        purchase_order_reference: "PO-42"
      )
      folio = create(
        :booking_folio,
        booking:,
        hotel:,
        name: "Acme Folio",
        folio_type: "external",
        payer_type: "company",
        is_primary: false,
        booking_billing_party: party,
        hotel_corporate_account: relationship
      )
      create(:folio_transaction, booking_folio: folio, amount: 240)

      get hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Direct bill planned: Acme Sdn Bhd · MYR 240.00")
      expect(Nokogiri::HTML(response.body).css("[data-slot='stay-view-financial-attention']")).to be_empty

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)

      badge = Nokogiri::HTML(response.body).at_css("[data-slot='stay-view-financial-signal']")
      expect(badge.text).to eq("Direct bill planned: Acme Sdn Bhd · MYR 240.00")
      expect(badge["data-variant"]).to eq("info")
    end

    it "does not query or emit financial data without permission" do
      booking = create(:booking, hotel:, guest_name: "Protected Financial Guest", check_in: Date.current, check_out: Date.current + 2.days)
      create(:booking_room, booking:, room_type:, room_number: "101")
      folio = create(:booking_folio, booking:, hotel:)
      create(:folio_transaction, booking_folio: folio, amount: 987.65)
      sql = []
      callback = lambda do |_name, _start, _finish, _id, payload|
        next if payload[:cached] || %w[SCHEMA TRANSACTION].include?(payload[:name])

        sql << payload[:sql]
      end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        get hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7)
      end

      expect(response).to have_http_status(:success)
      expect(sql.join(" ")).not_to include(
        "booking_folios", "booking_billing_parties", "booking_billing_terms", "hotel_corporate_accounts",
        "folio_transactions", "folio_forecasted_charges", "ar_invoices"
      )
      expect(response.body).not_to include(
        "987.65", "Balance due", "Payment due", "Credit", "Direct bill", "Projected settled",
        "Financial review required", "stay-view-financial"
      )
    end

    it "renders DND, priority, and full read-only housekeeping details in both views" do
      create(:room_status, hotel:, room_type:, room_number: "101", status: "dirty", priority: true, dnd: true, dnd_date: Date.current)
      create(
        :housekeeping_request,
        booking: nil,
        hotel:,
        room_type:,
        room_number: "101",
        status: "assigned",
        request_details: "Replace towels",
        metadata: { "assigned_to_name" => "Sam Lee" }
      )

      get hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Do not disturb", "Cleaning priority", "Replace towels", "Sam Lee")
      expect(response.body).not_to include("Assign room tasks", "Update task status")

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Do not disturb", "Cleaning priority", "Replace towels", "Sam Lee")
    end

    it "falls back safely for invalid URL state" do
      room_type

      get hotel_stay_view_path(hotel, view: "unknown", start_date: "not-a-date", days: 999, density: "huge")

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-density="compact"')
      expect(response.body).to include(Date.current.to_fs(:long))
    end

    it "renders only the board frame for a frame request" do
      room_type

      get hotel_stay_view_path(hotel), headers: { "Turbo-Frame" => "stay_view_board" }

      expect(response).to have_http_status(:success)
      expect(response.body).to match(/<turbo-frame[^>]+id="stay_view_board"/)
      # Frame requests render the board partial without the portal layout chrome.
      expect(response.body).not_to include("<html")
    end

    it "applies filters while retaining all room-type filter options" do
      suite = create(:room_type, hotel:, name: "Suite", room_numbers: [ "201" ])
      create(:room_status, hotel:, room_type:, room_number: "101", status: "dirty")
      create(:room_status, hotel:, room_type: suite, room_number: "201", status: "ready")

      get hotel_stay_view_path(hotel, physical_status: "dirty")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Room 101", "Suite")
      expect(response.body).not_to include("Room 201")
    end

    it "redacts booking identity and actions for readiness-only access" do
      role.role_permissions.delete_all
      grant("view_room_readiness")
      booking = create(:booking, hotel:, guest_name: "Sensitive Guest", check_in: Date.current, check_out: Date.current + 2.days)
      create(:booking_room, booking:, room_type:, room_number: "101")

      get hotel_stay_view_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Reserved")
      expect(response.body).not_to include("Sensitive Guest", "Move or reassign", "Change dates")
      expect(response.body).not_to include("#{room_type.id}_101-booking-actions")
      expect(response.body).not_to include("cell-actions-trigger")
    end

    it "rejects users without board access before loading the board" do
      role.role_permissions.delete_all

      get hotel_stay_view_path(hotel)

      expect(response).to redirect_to(root_path)
    end
  end

  describe "booking action sheets" do
    let(:booking) do
      create(:booking, hotel:, guest_name: "Ada Lovelace", check_in: Date.current, check_out: Date.current + 2.days).tap do |record|
        create(:booking_room, booking: record, room_type:, room_number: "101")
      end
    end

    it "renders move and date forms in the off-canvas frame" do
      get edit_hotel_stay_view_booking_move_path(hotel, booking), params: { return_to: hotel_stay_view_path(hotel) }, headers: { "Turbo-Frame" => "offcanvas_drawer" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include('turbo-frame id="offcanvas_drawer"', "Move or reassign stay", "Room 102")

      get edit_hotel_stay_view_booking_dates_path(hotel, booking), params: { return_to: hotel_stay_view_path(hotel) }, headers: { "Turbo-Frame" => "offcanvas_drawer" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Change stay dates", "assigned room stays the same")
    end

    it "moves a stay and selectively replaces unfiltered Timeline rows over Turbo Stream" do
      patch hotel_stay_view_booking_move_path(hotel, booking), params: {
        return_to: hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 7),
        booking: { check_in: Date.current + 3.days, room_assignment: "#{room_type.id}|102" }
      }, headers: turbo_headers

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body).to include(
        'target="stay_view_toolbar"',
        "target=\"stay_view_room_#{room_type.id}_101\"",
        "target=\"stay_view_room_#{room_type.id}_102\"",
        'target="offcanvas_drawer"',
        "Stay moved."
      )
      expect(response.body).not_to include('target="stay_view_board"')
      expect(booking.reload.check_in.to_date).to eq(Date.current + 3.days)
      expect(booking.booking_rooms.first.reload.room_number).to eq("102")
    end


    it "prefills and validates pointer move and resize proposals without mutation" do
      conflicting = create(:booking, hotel:, check_in: Date.current + 2.days, check_out: Date.current + 4.days)
      create(:booking_room, booking: conflicting, room_type:, room_number: "102")
      original_dates = [ booking.check_in, booking.check_out ]

      get edit_hotel_stay_view_booking_move_path(hotel, booking), params: {
        proposal: "pointer",
        booking: { check_in: Date.current + 2.days, room_assignment: "#{room_type.id}|102" }
      }, headers: { "Turbo-Frame" => "offcanvas_drawer" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Review the proposed room and date", "Room 102 is not available")
      expect(response.body).to include("value=\"#{Date.current + 2.days}\"")

      get edit_hotel_stay_view_booking_dates_path(hotel, booking), params: {
        proposal: "pointer",
        booking: { check_in: Date.current, check_out: Date.current + 3.days }
      }, headers: { "Turbo-Frame" => "offcanvas_drawer" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Review the proposed dates", "value=\"#{Date.current + 3.days}\"")
      expect([ booking.reload.check_in, booking.check_out ]).to eq(original_dates)
    end

    it "rejects a pointer proposal that names another hotel's room type" do
      other_hotel = create(:hotel)
      other_type = create(:room_type, hotel: other_hotel, room_numbers: [ "900" ])

      get edit_hotel_stay_view_booking_move_path(hotel, booking), params: {
        proposal: "pointer",
        booking: { check_in: Date.current, room_assignment: "#{other_type.id}|900" }
      }, headers: { "Turbo-Frame" => "offcanvas_drawer" }

      expect(response).to have_http_status(:not_found)
      expect(booking.reload.booking_rooms.first.room_number).to eq("101")
    end

    it "falls back to replacing the complete board when Timeline filters are active" do
      patch hotel_stay_view_booking_dates_path(hotel, booking), params: {
        return_to: hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 7, occupancy: :occupied),
        view: :timeline,
        start_date: Date.current,
        days: 7,
        occupancy: :occupied,
        booking: { check_in: Date.current + 1.day, check_out: Date.current + 3.days }
      }, headers: turbo_headers

      expect(response).to have_http_status(:success)
      expect(response.body).to include('target="stay_view_board"', 'target="offcanvas_drawer"')
      expect(response.body).not_to include('target="stay_view_toolbar"')
    end

    it "uses a 303 redirect for the HTML mutation fallback" do
      patch hotel_stay_view_booking_dates_path(hotel, booking), params: {
        return_to: hotel_stay_view_path(hotel, view: :rooms, date: Date.current),
        booking: { check_in: Date.current + 1.day, check_out: Date.current + 4.days }
      }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(hotel_stay_view_path(hotel, view: :rooms, date: Date.current))
    end

    it "returns 422 and keeps the proposal form when dates are invalid" do
      patch hotel_stay_view_booking_dates_path(hotel, booking), params: {
        return_to: hotel_stay_view_path(hotel),
        booking: { check_in: Date.current + 3.days, check_out: Date.current + 2.days }
      }, headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('target="offcanvas_drawer"', "Checkout must be after check-in")
      expect(booking.reload.check_in.to_date).to eq(Date.current)
    end
  end

  describe "room actions" do
    it "renders room-status and room-block sheets in the off-canvas frame" do
      get hotel_stay_view_room_status_path(hotel, room_type, "101"), params: { return_to: hotel_stay_view_path(hotel) }, headers: { "Turbo-Frame" => "offcanvas_drawer" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include('turbo-frame id="offcanvas_drawer"', "Change room status", "Physical status")

      get new_hotel_stay_view_room_block_path(hotel), params: {
        room_type_id: room_type.id,
        room_number: "101",
        return_to: hotel_stay_view_path(hotel)
      }, headers: { "Turbo-Frame" => "offcanvas_drawer" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Block room", "Block type", "Room 101")
    end

    it "updates room status and refreshes the board" do
      room_type

      patch hotel_stay_view_room_status_path(hotel, room_type, "101"), params: {
        return_to: hotel_stay_view_path(hotel, view: :rooms, date: Date.current),
        room_status: { status: "cleaning", notes: "In progress" }
      }, headers: turbo_headers

      expect(response).to have_http_status(:success)
      expect(response.body).to include('target="stay_view_board"', "Room status updated.")
      expect(hotel.room_statuses.find_by(room_type:, room_number: "101")).to have_attributes(status: "cleaning", notes: "In progress")
    end

    it "creates a room block through the authoritative command" do
      expect {
        post hotel_stay_view_room_blocks_path(hotel), params: {
          return_to: hotel_stay_view_path(hotel),
          room_block: {
            room_type_id: room_type.id,
            room_number: "101",
            start_date: Date.current + 1.day,
            end_date: Date.current + 2.days,
            block_type: "maintenance",
            reason: "Air-conditioning repair"
          }
        }, headers: turbo_headers
      }.to change(RoomBlock, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('target="stay_view_board"', "Room blocked.")
    end

    it "keeps the room-block sheet open with 422 validation errors" do
      post hotel_stay_view_room_blocks_path(hotel), params: {
        return_to: hotel_stay_view_path(hotel),
        room_block: {
          room_type_id: room_type.id,
          room_number: "101",
          start_date: Date.current + 2.days,
          end_date: Date.current,
          block_type: "maintenance",
          reason: ""
        }
      }, headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('target="offcanvas_drawer"', "could not be saved")
      expect(RoomBlock).not_to exist(room_number: "101")
    end

    it "blocks room mutations without the required capability" do
      role.role_permissions.joins(:permission).where(permissions: { slug: "manage_room_status" }).delete_all

      patch hotel_stay_view_room_status_path(hotel, room_type, "101"), params: {
        room_status: { status: "cleaning" }
      }

      expect(response).to redirect_to(root_path)
      expect(hotel.room_statuses).not_to exist(room_type:, room_number: "101")
    end

    it "returns 404 for a block owned by another hotel" do
      other_hotel = create(:hotel)
      other_type = create(:room_type, hotel: other_hotel, room_numbers: [ "900" ])
      block = create(:room_block, hotel: other_hotel, room_type: other_type, room_number: "900")

      get edit_hotel_stay_view_room_block_path(hotel, block)

      expect(response).to have_http_status(:not_found)
    end

    it "finishes and removes hotel-scoped blocks with whole-board refreshes" do
      first = create(:room_block, hotel:, room_type:, room_number: "101", start_date: Date.current + 1.day, end_date: Date.current + 2.days)
      second = create(:room_block, hotel:, room_type:, room_number: "102", start_date: Date.current + 3.days, end_date: Date.current + 4.days)

      post finish_hotel_stay_view_room_block_path(hotel, first), params: { return_to: hotel_stay_view_path(hotel) }, headers: turbo_headers
      expect(response).to have_http_status(:success)
      expect(first.reload.completed_at).to be_present

      expect {
        delete hotel_stay_view_room_block_path(hotel, second), params: { return_to: hotel_stay_view_path(hotel) }, headers: turbo_headers
      }.to change(RoomBlock, :count).by(-1)
      expect(response.body).to include('target="stay_view_board"', "Room block removed.")
    end
  end

  describe "housekeeping actions" do
    let!(:housekeeping_request) do
      create(
        :housekeeping_request,
        booking: nil,
        hotel:,
        room_type:,
        room_number: "101",
        status: "new",
        request_details: "Fresh towels"
      )
    end

    before do
      enable_housekeeping_feature
      grant("manage_housekeeping_tasks")
      grant("manage_requests")
    end

    it "renders separate assignment and status sheets" do
      housekeeper_role = create(:role, account: hotel.account, slug: "housekeeper", name: "Housekeeper")
      housekeeper = create(:user, account: hotel.account, name: "Sam Lee")
      create(:user_hotel_access, user: housekeeper, hotel:, role: housekeeper_role)

      get edit_hotel_stay_view_housekeeping_request_assignment_path(hotel, housekeeping_request),
        params: { return_to: hotel_stay_view_path(hotel) },
        headers: { "Turbo-Frame" => "offcanvas_drawer" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Assign room tasks", "all active housekeeping requests", "Sam Lee")

      get edit_hotel_stay_view_housekeeping_request_status_path(hotel, housekeeping_request),
        params: { return_to: hotel_stay_view_path(hotel) },
        headers: { "Turbo-Frame" => "offcanvas_drawer" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Update task status", "Fresh towels", "In progress", "Completed")
    end

    it "renders assignment and status actions according to their independent permissions" do
      assign_path = edit_hotel_stay_view_housekeeping_request_assignment_path(hotel, housekeeping_request)
      status_path = edit_hotel_stay_view_housekeeping_request_status_path(hotel, housekeeping_request)

      manage_requests = Permission.find_by!(slug: "manage_requests")
      role.role_permissions.find_by!(permission: manage_requests).destroy!

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)

      expect(response.body).to include(assign_path)
      expect(response.body).not_to include(status_path)

      manage_housekeeping = Permission.find_by!(slug: "manage_housekeeping_tasks")
      role.role_permissions.find_by!(permission: manage_housekeeping).destroy!
      create(:role_permission, role:, permission: manage_requests)

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)

      expect(response.body).not_to include(assign_path)
      expect(response.body).to include(status_path)
    end

    it "assigns room tasks through the authoritative service and selectively refreshes the room" do
      housekeeper_role = create(:role, account: hotel.account, slug: "housekeeper", name: "Housekeeper")
      housekeeper = create(:user, account: hotel.account, name: "Sam Lee")
      create(:user_hotel_access, user: housekeeper, hotel:, role: housekeeper_role)

      patch hotel_stay_view_housekeeping_request_assignment_path(hotel, housekeeping_request), params: {
        return_to: hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 7),
        assignment: { assigned_to: housekeeper.id }
      }, headers: turbo_headers

      expect(response).to have_http_status(:success)
      expect(response.body).to include("target=\"stay_view_room_#{room_type.id}_101\"", "Room tasks assigned.", "Sam Lee")
      expect(housekeeping_request.reload).to have_attributes(status: "assigned")
      expect(housekeeping_request.metadata).to include("assigned_to" => housekeeper.id, "assigned_to_name" => "Sam Lee")
    end

    it "updates status through the authoritative service and removes completed alerts" do
      create(:room_status, hotel:, room_type:, room_number: "101", status: "cleaning")

      patch hotel_stay_view_housekeeping_request_status_path(hotel, housekeeping_request), params: {
        return_to: hotel_stay_view_path(hotel, view: :rooms, date: Date.current),
        housekeeping_request: { status: "completed" }
      }, headers: turbo_headers

      expect(response).to have_http_status(:success)
      expect(response.body).to include('target="stay_view_board"', "Housekeeping status updated.")
      expect(response.body).not_to include("Fresh towels")
      expect(housekeeping_request.reload).to have_attributes(status: "completed")
      expect(hotel.room_statuses.find_by(room_type:, room_number: "101")).to have_attributes(status: "ready")
    end

    it "uses a 303 HTML fallback and rejects unavailable statuses" do
      patch hotel_stay_view_housekeeping_request_status_path(hotel, housekeeping_request), params: {
        return_to: hotel_stay_view_path(hotel, view: :rooms, date: Date.current),
        housekeeping_request: { status: "in_progress" }
      }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(hotel_stay_view_path(hotel, view: :rooms, date: Date.current))

      patch hotel_stay_view_housekeeping_request_status_path(hotel, housekeeping_request), params: {
        housekeeping_request: { status: "failed" }
      }, headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Status is not available")
    end

    it "does not allow another hotel's request through either workflow" do
      other_hotel = create(:hotel)
      other_type = create(:room_type, hotel: other_hotel, room_numbers: [ "900" ])
      other_request = create(
        :housekeeping_request,
        booking: nil,
        hotel: other_hotel,
        room_type: other_type,
        room_number: "900",
        status: "new"
      )

      get edit_hotel_stay_view_housekeeping_request_assignment_path(hotel, other_request)
      expect(response).to have_http_status(:not_found)

      get edit_hotel_stay_view_housekeeping_request_status_path(hotel, other_request)
      expect(response).to have_http_status(:not_found)
    end

    it "does not reopen completed or archived requests from stale action URLs" do
      housekeeping_request.update!(status: "completed")

      get edit_hotel_stay_view_housekeeping_request_status_path(hotel, housekeeping_request)
      expect(response).to have_http_status(:not_found)

      housekeeping_request.update!(status: "new", archived_at: Time.current)
      get edit_hotel_stay_view_housekeeping_request_assignment_path(hotel, housekeeping_request)
      expect(response).to have_http_status(:not_found)
    end
  end
end
