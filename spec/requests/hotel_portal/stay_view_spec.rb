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
    { "Accept" => Mime[:turbo_stream].to_s, "Turbo-Frame" => "booking_action_sheet" }
  end

  def expect_live_sheet_completion(frame: "booking_action_sheet")
    stream = Nokogiri::HTML(response.body).at_css("turbo-stream[action='complete_sheet'][target='#{frame}']")
    expect(stream).to be_present
    expect(stream["url"]).to be_nil
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

    it "surfaces both boat slots in the timeline bar popover, and hides them when boats are off" do
      hotel.update!(allow_boat_information: true)
      booking = create(:booking, hotel:, guest_name: "Ada Lovelace", check_in: Date.current, check_out: Date.current + 2.days)
      create(:booking_room, booking:, room_type:, room_number: "101")
      guest = create(:booking_guest, booking:, guest: create(:guest), is_primary: true)
      guest.update!(
        boat_in_at: hotel.hotel_time_zone.parse("#{Date.current} 08:00"),
        boat_out_at: hotel.hotel_time_zone.parse("#{Date.current + 2.days} 15:30")
      )

      get hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7)

      popover = Nokogiri::HTML(response.body).css("dl").find { |list| list.text.include?("Boat-in") }
      expect(popover).to be_present
      expect(popover.text).to include("Boat-in", "08:00", "Boat-out", "15:30")

      hotel.update!(allow_boat_information: false)
      get hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7)

      expect(response.body).not_to include("Boat-in")
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
      expect(response.body).to include("All room types", "All occupancy states", "All physical statuses")
      expect(response.body).not_to include("All booking statuses")

      document = Nokogiri::HTML(response.body)
      advanced = document.at_css("#stay-view-advanced-filters")
      expect(advanced.at_css("button").text.squish).to eq("Advanced filters")
      expect(advanced.at_css("#stay-view-advanced-filters-content")["hidden"]).to eq("hidden")
      expect(document.at_css("#rate_plan_id-select-menu")).to be_nil
      global_actions = document.at_css("[data-slot='stay-view-global-actions']")
      expect(global_actions.ancestors("#stay_view_toolbar")).to be_present
      expect(global_actions.at_css("a[href^='#{hotel_booking_action_walk_in_check_in_path(hotel)}']").text.squish).to eq("Walk-in")
      expect(global_actions.at_css("a[href^='#{hotel_booking_action_quick_booking_path(hotel)}']").text.squish).to eq("Add booking")
      operational_counts = document.css("[data-slot='stay-view-operational-count']")
      expect(operational_counts.map { |badge| badge["data-state"] }).to eq(
        %w[all vacant arrival occupied departure blocked dirty]
      )
      expect(operational_counts.map { |badge| badge.css("span").map(&:text) }).to eq(
        [ [ "All", "2" ], [ "Vacant", "1" ], [ "Arrival", "1" ], [ "Occupied", "0" ],
         [ "Departure", "0" ], [ "Blocked", "0" ], [ "Dirty", "0" ] ]
      )
      expect(document.at_css("button[aria-label='Stay View status guide']")).to be_present
      expect(document.at_css("#stay-view-status-guide-panel").text).to include("Arrival", "In-house", "Completed", "Do not disturb")
      expect(document.at_css("#stay-view-status-guide-panel").text).not_to include("Payment needed", "Company pays")
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

    it "renders editable on/off operational controls and a separate status-action trigger" do
      create(
        :room_status,
        hotel:,
        room_type:,
        room_number: "101",
        status: "inspection_failed",
        notes: "Reclean the bathroom",
        priority: true,
        priority_note: "Guest arriving early"
      )

      get hotel_stay_view_path(hotel, view: :rooms, date: Date.current)

      document = Nokogiri::HTML(response.body)
      room_id = "stay_view_room_#{room_type.id}_101"
      expect(document.at_css("button[aria-label='Cleaning priority: on — change']")).to be_present
      expect(document.at_css("button[aria-label='Do not disturb: off — change']")).to be_present
      expect(document.at_css("##{room_id}-priority-panel textarea[name='room_status[priority_note]']").text.strip).to eq("Guest arriving early")
      expect(document.at_css("##{room_id}-dnd-panel input[name='room_status[dnd]'][role='switch']")).to be_present
      expect(document.at_css("button[aria-label='Room status: Inspection failed — Reclean the bathroom — change']")).to be_present
      expect(document.at_css("##{room_id}-status-menu .dropdown-menu__header").text).to include(
        "Inspection reason",
        "Reclean the bathroom"
      )
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
      expect(add_booking_uri.path).to eq(hotel_booking_action_quick_booking_path(hotel))
      expect(Rack::Utils.parse_nested_query(add_booking_uri.query)).to include(
        "check_in" => Date.current.iso8601,
        "check_out" => (Date.current + 1.day).iso8601,
        "room_type_id" => room_type.id.to_s,
        "room_number" => "101",
        "source" => "stay_view"
      )
      expect(add_booking["data-turbo-frame"]).to eq("booking_action_sheet")

      today_trigger = document.at_css("##{room_id}-#{Date.current.iso8601}-cell-actions-trigger")
      expect(today_trigger["data-alignment"]).to eq("center")
    end

    it "keeps a checkout-only cell actionable and counts a departure room at the left edge" do
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
      expect(document.at_css("[data-state='departure']").css("span").map(&:text)).to eq([ "Departure", "1" ])
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
        [ [ "All", "0" ], [ "Vacant", "0" ], [ "Arrival", "0" ], [ "Occupied", "0" ],
         [ "Departure", "0" ], [ "Turnover", "0" ], [ "Blocked", "0" ], [ "Dirty", "0" ] ]
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
      expect(document.at_css("#rate_plan_id-select-menu")).to be_present
      expect(document.at_css("#rate_plan_id-select-menu").text).to include("Standard", "#{master_plan.name} — #{room_type.name}")
      advanced_trigger = document.at_css("#stay-view-advanced-filters-trigger")
      expect(advanced_trigger["class"].split).to include("w-auto", "shrink-0")
      expect(document.at_css("button[aria-label='Stay View status guide']")).to be_present
      expect(rates.size).to eq(7)
      expect(rates.first.text).to eq("145.00")
      expect(rates.first["aria-label"]).to end_with("145.00 #{master_plan.currency}")
      expect(rates[1].text).to eq(CurrencyFormatter.format(room_type.base_price, currency: master_plan.currency, symbol: false))

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)

      cards = Nokogiri::HTML(response.body)
      card_rates = cards.css("[data-testid='stay-view-room-cards'] [data-slot='stay-view-standard-rate']")
      expect(card_rates.map { |rate| rate.text.squish }).to eq([ "#{master_plan.currency} 145.00" ] * 2)
      expect(card_rates).to all(satisfy { |rate| rate.at_css("svg[aria-hidden='true']").present? })
      first_card = cards.at_css("[data-testid='stay-view-room-cards'] article")
      rate_row = first_card.at_css("[data-slot='stay-view-standard-rate']")
      expect(rate_row.parent.element_children.map { |node| node["data-slot"] }).to eq(
        %w[stay-view-room-identity stay-view-standard-rate stay-view-room-summary]
      )
    end

    it "filters both views to an explicitly selected linked rate plan" do
      grant("manage_rates")
      deluxe = room_type
      suite = create(:room_type, hotel:, name: "Suite", room_numbers: [ "201" ])
      flexible = create(:rate_plan, hotel:, name: "Flexible", currency: "USD")
      create(:room_type_rate_plan, room_type: deluxe, rate_plan: flexible)
      create(:room_rate, room_type: deluxe, rate_plan: flexible, date: Date.current, price: 175, currency: "USD")

      get hotel_stay_view_path(
        hotel, view: "timeline", start_date: Date.current, days: 7,
        rate_plan_id: flexible.id, room_type_id: suite.id
      )

      timeline = Nokogiri::HTML(response.body)
      rendered_groups = timeline.css("[data-slot='timeline-group']").map { |group| group.text.squish }
      expect(rendered_groups).to all(include("Deluxe"))
      expect(rendered_groups.none? { |group| group.include?("Suite") }).to be(true)
      expect(timeline.css("[data-slot='stay-view-standard-rate']").map(&:text)).to eq([ "175.00", *(%w[N/A] * 6) ])
      expect(timeline.at_css("#rate_plan_id-select-menu").text).to include("Flexible — Deluxe")
      expect(timeline.at_css("#stay-view-modes-tab-rooms")["href"]).to include("rate_plan_id=#{flexible.id}")
      expect(timeline.at_css("#stay-view-modes-tab-rooms")["href"]).not_to include("room_type_id")
      timeline_room_types = timeline.at_css("#room_type_id-select-menu").text
      expect(timeline_room_types).to include("All room types", deluxe.name)
      expect(timeline_room_types).not_to include(suite.name)

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current, rate_plan_id: flexible.id)

      rooms = Nokogiri::HTML(response.body)
      expect(rooms.css("[data-testid='stay-view-room-cards'] article h4").map(&:text)).to contain_exactly("101", "102")
      expect(rooms.css("[data-testid='stay-view-room-cards'] > section h3").map(&:text)).to eq([ deluxe.name ])
      expect(rooms.at_css("[data-slot='stay-view-room-workspace-toolbar'] input[name='rate_plan_id']")["value"]).to eq(flexible.id.to_s)
      room_view_room_types = rooms.at_css("#room_type_id-select-menu").text
      expect(room_view_room_types).to include("All room types", deluxe.name)
      expect(room_view_room_types).not_to include(suite.name)
      expect(rooms.css("[data-testid='stay-view-room-cards'] [data-slot='stay-view-standard-rate']").map { |rate| rate.text.squish }).to eq(
        [ "USD 175.00" ] * 2
      )
    end

    it "canonicalizes a cross-hotel rate-plan selection to Standard" do
      grant("manage_rates")
      room_type
      foreign_plan = create(:rate_plan, hotel: create(:hotel), name: "Foreign")

      get hotel_stay_view_path(
        hotel, view: "timeline", start_date: Date.current, days: 7, rate_plan_id: foreign_plan.id
      )

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("#rate_plan_id-select-menu .panel-select-menu__value").text.squish).to eq("Standard")
      expect(document.text).not_to include("Foreign")
      today = document.css("a").find { |link| link.text.squish == "Today" }
      expect(today["href"]).not_to include("rate_plan_id")
    end

    it "renders N/A for an authorized genuinely missing standard rate" do
      grant("manage_rates")
      room_type.update_column(:base_price, nil)

      get hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7)

      expect(response).to have_http_status(:success)
      expect(Nokogiri::HTML(response.body).css("[data-slot='stay-view-standard-rate']").map(&:text)).to eq([ "N/A" ] * 7)

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)

      expect(Nokogiri::HTML(response.body).css("[data-testid='stay-view-room-cards'] [data-slot='stay-view-standard-rate']").map { |rate| rate.text.squish }).to eq(
        [ "N/A" ] * 2
      )
    end

    it "omits the complete rate row from Room View without rate permission" do
      room_type

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)

      document = Nokogiri::HTML(response.body)
      expect(document.css("[data-testid='stay-view-room-cards'] [data-slot='stay-view-standard-rate']")).to be_empty
      expect(document.css("[data-testid='stay-view-room-cards'] svg").map { |icon| icon["class"] }).not_to include("banknote")
      expect(response.body).not_to include(room_type.base_price.to_s, "Standard nightly rate")
    end

    it "renders Room View from the shared projection" do
      room_type

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-testid="stay-view-room-cards"', "Room 101", "Room 102")
      expect(response.body).not_to include("stay-view-timeline")
    end

    it "shows primary-guest VIP, hotel blacklist, and same-hotel repeat context in both views" do
      guest = create(
        :guest,
        name: "Recognized Guest",
        vip: true,
        blacklisted: true,
        created_by_hotel: hotel,
        metadata: { "blacklisted_hotel_ids" => [ hotel.id ] }
      )
      prior_stay = create(
        :booking,
        hotel:,
        status: "completed",
        guest_name: guest.name,
        check_in: Date.current - 10.days,
        check_out: Date.current - 8.days
      )
      create(:booking_guest, booking: prior_stay, guest:, is_primary: true)
      booking = create(
        :booking,
        hotel:,
        guest_name: guest.name,
        check_in: Date.current,
        check_out: Date.current + 2.days
      )
      create(:booking_guest, booking:, guest:, is_primary: true)
      create(:booking_room, booking:, room_type:, room_number: "101")

      get hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7)

      timeline = Nokogiri::HTML(response.body)
      segment = timeline.at_css("#stay_view_booking_room_#{booking.booking_rooms.sole.id}")
      expect(segment.css("[id$='-trigger'] [data-slot='stay-view-guest-status']")).to be_empty
      expect(segment.css("[id$='-panel'] [data-slot='stay-view-guest-status']").map { |status| status["data-status"] }).to eq(
        %w[blacklisted vip repeat]
      )
      expect(segment.css("dt").none? { |node| node.text.squish == "Guest status" }).to be(true)
      expect(segment.at_css("[id$='-panel'] [aria-label='Blacklisted guest']")).to be_present
      expect(segment.at_css("[id$='-panel'] [aria-label='VIP guest']")).to be_present
      expect(segment.at_css("[id$='-panel'] [aria-label='Repeat guest']")).to be_present
      expect(timeline.at_css("#stay-view-status-guide-panel").text.squish).to include(
        "Guest status", "Blacklisted", "VIP", "Repeat"
      )

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)

      room_item = Nokogiri::HTML(response.body).at_css(
        "#stay_view_room_#{room_type.id}_101 [data-slot='stay-view-room-booking-item']"
      )
      statuses = room_item.css("[data-slot='stay-view-guest-status']")
      expect(statuses.map { |status| [ status["data-status"], status.text ] }).to eq(
        [ [ "blacklisted", "Blacklisted" ], [ "vip", "VIP" ], [ "repeat", "Repeat" ] ]
      )
      expect(statuses.map { |status| status["data-variant"] }).to eq(%w[destructive warning info])
      expect(room_item["aria-label"]).to include("guest status Blacklisted, VIP, and Repeat")
    end

    it "groups Room View by room type by default and flattens it on request" do
      create(:room_type, hotel:, name: "Suite", room_numbers: [ "201" ])
      room_type

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)
      grouped = Nokogiri::HTML(response.body)
      expect(grouped.css("[data-testid='stay-view-room-cards'] section")).not_to be_empty
      workspace = grouped.at_css("[data-slot='stay-view-room-workspace-toolbar']")
      expect(workspace["class"].split).not_to include("rounded-lg", "border", "bg-card", "p-2")
      expect(workspace.css("span").map { |span| span.text.squish }).not_to include("Grouping")
      expect(workspace.at_css("#room_type_id-select-menu")).to be_present
      toggle = workspace.at_css("#stay-view-room-grouping")
      expect(toggle["aria-label"]).to eq("Room card grouping")
      expect(toggle["data-variant"]).to eq("outline")
      expect(toggle["data-spacing"]).to eq("0")
      expect(toggle.css("button").map { |button| [ button.text.squish, button["aria-pressed"] ] }).to eq(
        [ [ "Grouped", "true" ], [ "Ungrouped", "false" ] ]
      )
      expect(toggle.css("button svg[aria-hidden='true']").size).to eq(2)
      expect(toggle.css("button")).to all(satisfy { |button| button["class"].split.include?("panel-toggle") })
      expect(workspace.text).to include("3 rooms")
      advanced = grouped.at_css("#stay-view-advanced-filters-content")
      expect(advanced.text).to include("Room state", "Physical status")
      expect(advanced.text).not_to include("Occupancy")

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current, group_by: "none")
      flat = Nokogiri::HTML(response.body)
      expect(flat.css("[data-testid='stay-view-room-cards'] > section")).to be_empty
      expect(flat.css("[data-testid='stay-view-room-cards'] article h3").map(&:text)).to contain_exactly("101", "102", "201")
      expect(response.body).to include("Room 101", "Room 201")
    end

    it "renders a compact turnover panel without a room action menu or footer" do
      departing = create(
        :booking,
        hotel:,
        status: "completed",
        guest_name: "Departing Guest",
        adults: 2,
        children: 1,
        check_in: hotel.hotel_time_zone.local(2026, 7, 14, 15),
        check_out: hotel.hotel_time_zone.local(2026, 7, 16, 12),
        checked_out_at: hotel.hotel_time_zone.local(2026, 7, 16, 7, 55)
      )
      arriving = create(
        :booking,
        hotel:,
        status: "confirmed",
        guest_name: "Arriving Guest",
        adults: 1,
        children: 0,
        check_in: hotel.hotel_time_zone.local(2026, 7, 16, 15),
        check_out: hotel.hotel_time_zone.local(2026, 7, 18, 12),
        source: "walk_in"
      )
      create(:booking_room, booking: departing, room_type:, room_number: "101")
      create(:booking_room, booking: arriving, room_type:, room_number: "101")
      create(
        :booking_guest,
        booking: departing,
        is_primary: true,
        boat_out_at: hotel.hotel_time_zone.local(2026, 7, 16, 8, 30)
      )
      create(
        :booking_guest,
        booking: arriving,
        is_primary: true,
        boat_in_at: hotel.hotel_time_zone.local(2026, 7, 16, 14, 30)
      )

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)

      document = Nokogiri::HTML(response.body)
      room = document.at_css("#stay_view_room_#{room_type.id}_101")
      expect(room["data-room-state"]).to eq("turnover")
      expect(room.at_css("[data-slot='stay-view-room-identity']")["class"]).to include(
        "grid-cols-[minmax(0,1fr)_auto]"
      )
      expect(room.at_css("[data-slot='stay-view-room-summary']")["data-layout"]).to eq("split_controls")
      expect(room.at_css("[data-slot='stay-view-room-turnover']").text).to include(
        "Departing Guest", "Departed at 07:55", "2 adults, 1 child", "Boat-out 08:30",
        "Arriving Guest", "Arrives today at 15:00", "1 adult, 0 children", "Boat-in 14:30"
      )
      turnover_panel = room.at_css("[data-slot='stay-view-room-turnover']")
      expect(turnover_panel["class"].split).to include("divide-y", "divide-border")
      booking_items = room.css("a[data-slot='stay-view-room-booking-item']")
      expect(booking_items.size).to eq(2)
      expect(booking_items.map { |item| item.at_css("[data-slot='stay-view-room-pax']").text.squish }).to eq(%w[3 1])
      booking_items.each do |item|
        expect(item["class"].split).not_to include("border-0")
        expect(item.at_css("[role='tooltip'][popover='manual']")).to be_present
        expect(Rack::Utils.parse_nested_query(URI.parse(item["href"]).query)).to include("source" => "stay_view")
      end
      expect(room.at_css("button[aria-label='Actions for room 101']")).to be_nil
      expect(room.at_css("[data-slot='stay-view-room-footer']")).to be_nil
      expect(response.body).to include("xl:grid-cols-5")
      expect(room["class"].split).to include("h-full")
      expect(response.body).not_to include("grid items-start gap-4")
    end

    it "renders date-aware ButtonGroups only in a vacant card footer" do
      room_type
      expected = {
        Date.current - 1.day => %w[Backdated Block],
        Date.current => [ "Walk-in", "Book", "Block" ],
        Date.current + 1.day => %w[Book Block]
      }

      expected.each do |date, labels|
        get hotel_stay_view_path(hotel, view: "rooms", date:)

        room = Nokogiri::HTML(response.body).at_css("#stay_view_room_#{room_type.id}_101")
        activity = room.at_css("[data-slot='stay-view-room-activity']")
        footer = room.at_css("[data-slot='stay-view-room-footer']")
        expect(activity.text).to include("No activity today")
        expect(footer.css("[data-slot='button-group'] a").map { |item| item.text.squish }).to eq(labels)
        footer.css("[data-slot='button-group'] a").each do |item|
          expect(Rack::Utils.parse_nested_query(URI.parse(item["href"]).query)).to include("source" => "stay_view")
        end
      end
    end

    it "renders the same date-aware footer for a departure without an arrival" do
      departing = create(
        :booking,
        hotel:,
        status: "completed",
        guest_name: "Departing Guest",
        check_in: Date.current - 2.days,
        check_out: Date.current
      )
      create(:booking_room, booking: departing, room_type:, room_number: "101")

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)

      room = Nokogiri::HTML(response.body).at_css("#stay_view_room_#{room_type.id}_101")
      expect(room["data-room-state"]).to eq("departure")
      expect(room.at_css("[data-context='departure']").text).to include("Departing Guest", "Departed")
      expect(room.css("[data-slot='stay-view-room-footer'] a").map { |item| item.text.squish }).to eq(
        [ "Walk-in", "Book", "Block" ]
      )
    end

    it "suppresses the footer for an occupied stay" do
      occupied = create(
        :booking,
        hotel:,
        status: "checked_in",
        guest_name: "Occupied Guest",
        check_in: Date.current - 1.day,
        check_out: Date.current + 1.day
      )
      create(:booking_room, booking: occupied, room_type:, room_number: "101")

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)

      room = Nokogiri::HTML(response.body).at_css("#stay_view_room_#{room_type.id}_101")
      expect(room["data-room-state"]).to eq("occupied")
      expect(room.at_css("[data-context='occupied']").text).to include("Occupied Guest", "Stays until")
      expect(room.at_css("[data-slot='stay-view-room-footer']")).to be_nil
    end

    it "uses actual lifecycle history for past Room View states and footer eligibility" do
      zone = hotel.hotel_time_zone
      actual_arrival = Date.current - 3.days
      scheduled_departure = Date.current - 2.days
      actual_departure = Date.current - 1.day
      completed = create(
        :booking,
        hotel:,
        status: "completed",
        guest_name: "Historical Guest",
        check_in: zone.local(actual_arrival.year, actual_arrival.month, actual_arrival.day, 15),
        check_out: zone.local(scheduled_departure.year, scheduled_departure.month, scheduled_departure.day, 12),
        checked_in_at: zone.local(actual_arrival.year, actual_arrival.month, actual_arrival.day, 15),
        checked_out_at: zone.local(actual_departure.year, actual_departure.month, actual_departure.day, 8)
      )
      create(:booking_room, booking: completed, room_type:, room_number: "101")

      get hotel_stay_view_path(hotel, view: "rooms", date: actual_arrival)
      arrival = Nokogiri::HTML(response.body).at_css("#stay_view_room_#{room_type.id}_101")
      expect(arrival["data-room-state"]).to eq("arrival")
      expect(arrival.at_css("[data-context='arrival']").text).to include("Historical Guest", "Arrived")
      expect(arrival.at_css("[data-slot='stay-view-room-footer']")).to be_nil

      get hotel_stay_view_path(hotel, view: "rooms", date: scheduled_departure)
      occupied = Nokogiri::HTML(response.body).at_css("#stay_view_room_#{room_type.id}_101")
      expect(occupied["data-room-state"]).to eq("occupied")
      expect(occupied.at_css("[data-context='occupied']").text).to include(
        "Historical Guest", "Stayed until #{actual_departure.to_fs(:medium)}"
      )
      expect(occupied.at_css("[data-slot='stay-view-room-footer']")).to be_nil

      get hotel_stay_view_path(hotel, view: "rooms", date: actual_departure)
      departure = Nokogiri::HTML(response.body).at_css("#stay_view_room_#{room_type.id}_101")
      expect(departure["data-room-state"]).to eq("departure")
      expect(departure.at_css("[data-context='departure']").text).to include("Historical Guest", "Departed")
      expect(departure.css("[data-slot='stay-view-room-footer'] a").map { |item| item.text.squish }).to eq(
        %w[Backdated Block]
      )
    end

    it "uses the six-state Room View filter while Timeline retains occupancy filtering" do
      arriving = create(
        :booking,
        hotel:,
        status: "confirmed",
        guest_name: "Arriving Guest",
        check_in: Date.current,
        check_out: Date.current + 1.day
      )
      create(:booking_room, booking: arriving, room_type:, room_number: "101")

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current, room_state: "arrival")

      room_view = Nokogiri::HTML(response.body)
      expect(response.body).to include("Room state", "All room states", "Turnover")
      expect(response.body).not_to include("All occupancy states")
      expect(room_view.css("[data-testid='stay-view-room-cards'] article").map { |card| card["data-room-state"] }).to eq([ "arrival" ])

      get hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, occupancy: "arrival")

      expect(response.body).to include("Occupancy", "All occupancy states")
      expect(response.body).not_to include("All room states")
    end

    it "renders authorized financial details in the Timeline popover and a full badge in Room View" do
      grant("view_financial_status")
      booking = create(:booking, hotel:, guest_name: "Financial Guest", check_in: Date.current, check_out: Date.current + 2.days)
      create(:booking_room, booking:, room_type:, room_number: "101")
      folio = create(:booking_folio, booking:, hotel:)
      create(:booking_guest, booking:, guest: create(:guest, name: "Financial Guest"), is_primary: true)
      create(:folio_transaction, booking_folio: folio, amount: 240)

      get hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7)

      timeline = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:success)
      expect(timeline.css("[id$='-trigger'] [data-slot='stay-view-financial-attention']")).to be_empty
      expect(response.body).to include("Collect MYR 240.00 · Financial Guest")

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)

      room_view = Nokogiri::HTML(response.body)
      badge = room_view.at_css("[data-slot='stay-view-financial-signal']")
      expect(badge.text).to eq("Collect MYR 240.00 · Financial Guest")
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
        relationship_type: "direct_bill"
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
        label: "Acme Folio",
        folio_type: "external",
        payer_type: "company",
        is_primary: false,
        booking_billing_party: party,
        hotel_corporate_account: relationship
      )
      create(:folio_transaction, booking_folio: folio, amount: 240)

      get hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Company pays MYR 240.00 · Acme Sdn Bhd")
      expect(Nokogiri::HTML(response.body).css("[data-slot='stay-view-financial-attention']")).to be_empty

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)

      badge = Nokogiri::HTML(response.body).at_css("[data-slot='stay-view-financial-signal']")
      expect(badge.text).to eq("Company pays MYR 240.00 · Acme Sdn Bhd")
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
        "987.65", "Collect MYR", "Unpaid MYR", "Refund MYR", "Company pays MYR", "Invoiced MYR",
        "Nothing due", "Check folio", "stay-view-financial"
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

    it "surfaces the status-appropriate migrated lifecycle action in the booking summary Sheet" do
      booking = create(
        :booking,
        hotel:,
        guest_name: "Lifecycle Guest",
        check_in: Date.current - 1.day,
        check_out: Date.current + 1.day
      )
      create(:booking_room, booking:, room_type:, room_number: "101")
      expected = {
        "confirmed" => "Check-in",
        "review_no_show" => "Mark No-show",
        "checked_in" => "Check-out",
        "review_due_out" => "Review Late Checkout",
        "checkout_required" => "Complete Checkout"
      }
      expected.each do |status, label|
        booking.update_column(:status, status)
        return_to = hotel_stay_view_path(hotel, view: "rooms", date: Date.current)
        get hotel_booking_action_show_booking_path(hotel, booking, source: "stay_view", return_to:)

        document = Nokogiri::HTML(response.body)
        expect(document.at_css("turbo-frame#booking_action_sheet")).to be_present
        control_labels = document.css("a, button").map { |control| control.text.squish }
        expect(control_labels).to include(label), "expected #{label.inspect} for #{status}"
      end
    end

    it "does not expose lifecycle actions when arrival access lacks manage bookings" do
      role.role_permissions.joins(:permission).where(permissions: { slug: "manage_bookings" }).delete_all
      booking = create(:booking, hotel:, status: "confirmed", check_in: Date.current, check_out: Date.current + 1.day)
      create(:booking_room, booking:, room_type:, room_number: "101")

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)

      document = Nokogiri::HTML(response.body)
      item = document.at_css("#stay_view_room_#{room_type.id}_101 a[data-slot='stay-view-room-booking-item']")
      expect(item).to be_present

      get item["href"]
      control_labels = Nokogiri::HTML(response.body).css("a, button").map { |control| control.text.squish }
      expect(control_labels).not_to include("Check-in", "Cancel", "Mark No-show", "Check-out")
    end

    it "rejects users without board access before loading the board" do
      role.role_permissions.delete_all

      get hotel_stay_view_path(hotel)

      expect(response).to redirect_to(root_path)
    end
  end

  describe "room actions" do
    it "renders room-status and room-block actions as native Sheets" do
      get hotel_stay_view_room_status_path(hotel, room_type, "101"), params: { return_to: hotel_stay_view_path(hotel) }, headers: { "Turbo-Frame" => "booking_action_sheet" }
      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#booking_action_sheet dialog#stay-view-room-status-sheet[data-controller='panels-ui--sheet']")).to be_present
      expect(response.body).to include("Change room status", "Physical status")

      get new_hotel_stay_view_room_block_path(hotel), params: {
        room_type_id: room_type.id,
        room_number: "101",
        return_to: hotel_stay_view_path(hotel)
      }, headers: { "Turbo-Frame" => "booking_action_sheet" }
      expect(response).to have_http_status(:success)
      expect(Nokogiri::HTML(response.body).at_css("turbo-frame#booking_action_sheet dialog#stay-view-room-block-sheet[data-controller='panels-ui--sheet']")).to be_present
      expect(response.body).to include("Block room", "Block type", "Room 101")
    end

    it "falls back to the primary Sheet frame for direct room-action requests" do
      get hotel_stay_view_room_status_path(hotel, room_type, "101"), params: { return_to: hotel_stay_view_path(hotel) }

      expect(response).to have_http_status(:success)
      expect(Nokogiri::HTML(response.body).at_css("turbo-frame#booking_action_sheet dialog#stay-view-room-status-sheet")).to be_present
    end

    it "keeps an existing custom room-block type selected and saveable" do
      block = create(:room_block, hotel:, room_type:, room_number: "101")
      block.update_column(:block_type, "storm_recovery")

      get edit_hotel_stay_view_room_block_path(hotel, block), params: {
        return_to: hotel_stay_view_path(hotel, view: :rooms, date: Date.current)
      }, headers: { "Turbo-Frame" => "booking_action_sheet" }

      document = Nokogiri::HTML(response.body)
      option = document.at_css("select[name='room_block[block_type]'] option[value='storm_recovery']")
      expect(option).to be_present
      expect(option.text).to eq("Storm recovery (existing)")
      expect(option["selected"]).to eq("selected")

      patch hotel_stay_view_room_block_path(hotel, block), params: {
        return_to: hotel_stay_view_path(hotel, view: :rooms, date: Date.current),
        room_block: {
          room_type_id: room_type.id,
          room_number: "101",
          start_date: block.start_date,
          end_date: block.end_date,
          block_type: "storm_recovery",
          reason: "Weather damage repaired"
        }
      }, headers: turbo_headers

      expect(response).to have_http_status(:success)
      expect(block.reload).to have_attributes(block_type: "storm_recovery", reason: "Weather damage repaired")
    end

    it "updates room status and refreshes the board" do
      room_type

      patch hotel_stay_view_room_status_path(hotel, room_type, "101"), params: {
        return_to: hotel_stay_view_path(hotel, view: :rooms, date: Date.current),
        room_status: { status: "cleaning", notes: "In progress" }
      }, headers: turbo_headers

      expect(response).to have_http_status(:success)
      expect(response.body).to include('target="stay_view_board"', "Room status updated.")
      expect_live_sheet_completion
      expect(hotel.room_statuses.find_by(room_type:, room_number: "101")).to have_attributes(status: "cleaning", notes: "In progress")
    end

    it "updates priority and DND through stateful flag controls without overwriting the status note" do
      room_status = create(
        :room_status,
        hotel:,
        room_type:,
        room_number: "101",
        status: "inspection_failed",
        notes: "Dust on headboard"
      )

      patch hotel_stay_view_room_status_path(hotel, room_type, "101"), params: {
        flag_control: "priority",
        return_to: hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 7),
        view: :timeline,
        start_date: Date.current,
        days: 7,
        room_status: { priority: "1", priority_note: "Prepare before noon" }
      }, headers: turbo_headers

      expect(response).to have_http_status(:success)
      expect(response.body).to include("target=\"stay_view_room_#{room_type.id}_101\"", "Room status updated.")
      expect(response.body).not_to include('target="stay_view_board"')
      expect(room_status.reload).to have_attributes(
        priority: true,
        priority_note: "Prepare before noon",
        notes: "Dust on headboard"
      )

      patch hotel_stay_view_room_status_path(hotel, room_type, "101"), params: {
        flag_control: "dnd",
        return_to: hotel_stay_view_path(hotel, view: :rooms, date: Date.current),
        view: :rooms,
        date: Date.current,
        room_status: { dnd: "1" }
      }, headers: turbo_headers

      expect(response).to have_http_status(:success)
      expect(response.body).to include('target="stay_view_board"')
      expect(room_status.reload).to have_attributes(dnd: true, dnd_date: Date.current)
    end

    it "uses the HTML fallback for flag updates" do
      room_status = create(:room_status, hotel:, room_type:, room_number: "101", priority: false)
      return_to = hotel_stay_view_path(hotel, view: :rooms, date: Date.current)

      patch hotel_stay_view_room_status_path(hotel, room_type, "101"), params: {
        flag_control: "priority",
        return_to:,
        room_status: { priority: "1", priority_note: "Early arrival" }
      }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(return_to)
      expect(room_status.reload).to have_attributes(priority: true, priority_note: "Early arrival")
    end

    it "returns a flag-control error without replacing the off-canvas sheet" do
      room_type
      failure = OpenStruct.new(success?: false, error: "Operational flag could not be saved")
      allow(Rooms::UpdateStatus).to receive(:new).and_return(instance_double(Rooms::UpdateStatus, call: failure))

      patch hotel_stay_view_room_status_path(hotel, room_type, "101"), params: {
        flag_control: "priority",
        room_status: { priority: "1" }
      }, headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Operational flag could not be saved")
      expect(response.body).not_to include('target="booking_action_sheet"')
    end

    it "redacts operational notes and flag indicators without readiness permission" do
      create(
        :room_status,
        hotel:,
        room_type:,
        room_number: "101",
        status: "inspection_failed",
        notes: "Sensitive inspection reason",
        priority: true,
        priority_note: "Sensitive priority instructions"
      )
      role.role_permissions.joins(:permission).where(permissions: { slug: "manage_room_status" }).delete_all

      get hotel_stay_view_path(hotel, view: :rooms, date: Date.current)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include(
        "Sensitive inspection reason",
        "Sensitive priority instructions",
        "stay-view-priority-indicator",
        "stay-view-dnd-indicator"
      )
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
      expect_live_sheet_completion
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
      expect(response.body).to include('target="booking_action_sheet"', "could not be saved", "stay-view-room-block-sheet")
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("input[name='room_block[start_date]']")["value"]).to eq((Date.current + 2.days).iso8601)
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
      expect_live_sheet_completion
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
      grant("dispatch_housekeeping_tasks")
      grant("manage_requests")
    end

    it "renders separate assignment and status sheets" do
      housekeeper_role = create(:role, account: hotel.account, slug: "housekeeper", name: "Housekeeper")
      housekeeper = create(:user, account: hotel.account, name: "Sam Lee")
      create(:user_hotel_access, user: housekeeper, hotel:, role: housekeeper_role)

      get edit_hotel_stay_view_housekeeping_request_assignment_path(hotel, housekeeping_request),
        params: { return_to: hotel_stay_view_path(hotel) },
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(Nokogiri::HTML(response.body).at_css("dialog#stay-view-housekeeping-assignment-sheet[data-controller='panels-ui--sheet']")).to be_present
      expect(response.body).to include("Assign room tasks", "all active housekeeping requests", "Sam Lee")

      get edit_hotel_stay_view_housekeeping_request_status_path(hotel, housekeeping_request),
        params: { return_to: hotel_stay_view_path(hotel) },
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(Nokogiri::HTML(response.body).at_css("dialog#stay-view-housekeeping-status-sheet[data-controller='panels-ui--sheet']")).to be_present
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

      manage_housekeeping = Permission.find_by!(slug: "dispatch_housekeeping_tasks")
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
      expect_live_sheet_completion
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
      expect_live_sheet_completion
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
