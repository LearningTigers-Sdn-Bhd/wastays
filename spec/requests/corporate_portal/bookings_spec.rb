# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CorporatePortal::Bookings", type: :request do
  let(:user) { create(:user, :corporate) }
  let(:hotel) { create(:hotel, status: "live") }
  # Booking for a client is a permission the hotel grants; without it the portal
  # refuses, which the gate specs at the bottom cover.
  let(:relationship) do
    create(:hotel_corporate_account, corporate_account: user.account, hotel: hotel,
                                     agent_booking_enabled: true)
  end

  let!(:room_type) do
    Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "Deluxe", room_number_mode: "custom", quantity: 4, base_price: 250.0,
                    max_adults: 3, max_children: 2, room_numbers: %w[101 102 103 104] }
    )
  end

  let(:check_in) { Date.current + 14 }
  let(:check_out) { Date.current + 16 }

  before do
    relationship
    sign_in_as(user)
  end

  def room_detail(*guests)
    { rooms_detail: guests.each_with_index.to_h { |people, index|
      [ index.to_s, { guests: people.each_with_index.to_h { |attrs, i| [ i.to_s, attrs ] } } ]
    } }
  end

  def search_params(overrides = {})
    { hotel_relationship_id: relationship.id, check_in: check_in.to_s,
      check_out: check_out.to_s, adults: 2 }.merge(overrides)
  end

  # The wizard's URL: the stay's hotel and dates, plus a cart of lines.
  def stay_params(overrides = {})
    { hotel_relationship_id: relationship.id, check_in: check_in.to_s, check_out: check_out.to_s }.merge(overrides)
  end

  def cart_of(*lines)
    lines.each_with_index.to_h { |line, index| [ index.to_s, { room_type_id: room_type.id, adults: 2, quantity: 1 }.merge(line) ] }
  end

  def guests_step(*lines)
    new_corporate_booking_path(stay_params(step: "guests", lines: cart_of(*(lines.presence || [ {} ]))))
  end

  it "offers the hotels this account is linked to" do
    get new_corporate_booking_path

    expect(response).to have_http_status(:success)
    # Faker hands out names like "Cormier-O'Reilly"; the rendered page escapes
    # the apostrophe, so compare against the escaped form.
    expect(response.body).to include(ERB::Util.html_escape(hotel.name))
  end

  describe "the hotel field, with a single linked hotel" do
    it "shows it read-only rather than asking, and still submits its id" do
      get new_corporate_booking_path

      expect(response.body).to include('readonly="readonly"')
      hidden_field = response.parsed_body.at_css('input[type="hidden"][name="hotel_relationship_id"]')
      expect(hidden_field["value"]).to eq(relationship.id.to_s)
    end

    it "searches it without the agent having picked anything" do
      get new_corporate_booking_path(check_in: check_in.to_s, check_out: check_out.to_s, adults: 2)

      expect(response.body).to include("Deluxe")
    end
  end

  it "offers a real choice once linked to more than one hotel" do
    second_hotel = create(:hotel, status: "live")
    create(:hotel_corporate_account, corporate_account: user.account, hotel: second_hotel,
                                     agent_booking_enabled: true)

    get new_corporate_booking_path

    expect(response.body).not_to include('readonly="readonly"')
    expect(response.body).to include(ERB::Util.html_escape(hotel.name))
    expect(response.body).to include(ERB::Util.html_escape(second_hotel.name))
  end

  it "labels the ID field IC by default, matching the preselected nationality" do
    get guests_step

    expect(response.body).to include("agent-guest-identity")
    expect(response.body).to include("IC number")
    expect(response.body).not_to include("IC / Passport")
  end

  it "shows what is available for the dates, priced for the stay" do
    get new_corporate_booking_path(stay_params(step: "rooms", stage: "rate", add_room_type_id: room_type.id,
                                               add_adults: 2, add_quantity: 1))

    expect(response.body).to include("Deluxe")
    expect(response.body).to include("2 nights")
    # Payment follows the billing relationship, not a card taken here -- but the
    # page no longer needs to say so; the deadline panel makes the mechanics
    # explicit once a booking exists.
    expect(response.body).not_to include("Payment is not taken here")
  end

  describe "tax visibility" do
    before do
      hotel.update!(sst_enabled: true, tourism_tax_enabled: true, tourism_tax_amount: 10.0)
      room_revenue = TransactionCodes::Resolver.for(hotel).room_revenue
      room_revenue.update!(is_taxable: true)
      TransactionCodes::AssignTaxRules.call(
        transaction_code: room_revenue, keys: %w[primary:sst_tax primary:tourism_tax]
      )
    end

    it "names SST on the priced option and flags tourism tax as a checkout note" do
      get new_corporate_booking_path(stay_params(step: "rooms", stage: "rate", add_room_type_id: room_type.id,
                                                 add_adults: 2, add_quantity: 1))

      expect(response.body).to include("SST 8%")
      expect(response.body).to include("tourism tax")
      expect(response.body).to include("outside Malaysia")
    end

    it "breaks the confirmed booking's total into room charges and tax" do
      post corporate_bookings_path, params: {
        hotel_relationship_id: relationship.id,
        booking: {
          room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
          adults: 2, children: 0, rooms: 1
        }.merge(room_detail([ { name: "Aisha Rahman", phone: "+60123456789" } ]))
      }
      booking = Booking.last

      get corporate_booking_path(booking)

      expect(response.body).to include("Room charges")
      expect(response.body).to include("SST")
      expect(response.body).to include("Tourism tax")
    end
  end

  it "asks for nationality with a searchable field per guest, Malaysia preselected" do
    get guests_step

    expect(response.body).to include("Nationality")
    expect(response.body).not_to include("Nationality (optional)")
    expect(response.body).to include('name="booking[rooms_detail][0][guests][0][country]"')
    expect(response.body).to include('name="booking[rooms_detail][0][guests][1][country]"')
    expect(response.body).to include('selected="selected" value="Malaysia"')
  end

  it "books a room for a guest and attributes it to the account" do
    expect {
      post corporate_bookings_path, params: {
        hotel_relationship_id: relationship.id,
        booking: {
          room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
          adults: 2, children: 0, rooms: 1
        }.merge(room_detail([ { name: "Aisha Rahman", phone: "+60123456789", email: "aisha@example.com" } ]))
      }
    }.to change(Booking, :count).by(1)

    booking = Booking.order(:id).last
    expect(booking.hotel_corporate_account_id).to eq(relationship.id)
    expect(booking.guest_name).to eq("Aisha Rahman")
    expect(booking.hotel_id).to eq(hotel.id)
    expect(response).to redirect_to(corporate_booking_path(booking))
  end

  # Optional: it is the one lever available before checkout for pricing
  # tourism tax accurately instead of assuming every guest is foreign.
  it "records the lead's nationality on the booking and a companion's on their own guest record" do
    post corporate_bookings_path, params: {
      hotel_relationship_id: relationship.id,
      booking: {
        room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
        adults: 2, children: 0, rooms: 1
      }.merge(room_detail([
        { name: "Aisha Rahman", phone: "+60123456789", country: "Malaysia" },
        { name: "Priya Singh", country: "India", date_of_birth: "1990-05-01" }
      ]))
    }

    booking = Booking.order(:id).last
    expect(booking.guest_country).to eq("Malaysia")
    companion = booking.booking_guests.find_by(name_snapshot: "Priya Singh")
    expect(companion.country_snapshot).to eq("India")
  end

  describe "identity: IC number vs. passport number" do
    # The first six digits of a Malaysian IC are the birthdate; Guest already
    # knows how to read it (Guest#populate_date_of_birth_from_malaysian_ic),
    # so a Malaysian nationality plus an IC number is enough on its own --
    # the agent should not have to also type a date of birth.
    it "derives date of birth from a Malaysian IC without one being typed" do
      post corporate_bookings_path, params: {
        hotel_relationship_id: relationship.id,
        booking: {
          room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
          adults: 1, children: 0, rooms: 1
        }.merge(room_detail([
          { name: "Aisha Rahman", phone: "+60123456789", country: "Malaysia", government_id: "900101-14-5523" }
        ]))
      }

      booking = Booking.order(:id).last
      guest = booking.booking_guests.sole.guest
      expect(guest.document_type).to eq("malaysian_nric")
      expect(guest.government_id).to eq("900101-14-5523")
      expect(guest.date_of_birth).to eq(Date.new(1990, 1, 1))
    end

    # The client-side script blocks this before it can be submitted; this is
    # the guard for a request that skips the browser entirely.
    it "does not derive a date of birth from an IC containing letters" do
      post corporate_bookings_path, params: {
        hotel_relationship_id: relationship.id,
        booking: {
          room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
          adults: 1, children: 0, rooms: 1
        }.merge(room_detail([
          { name: "Aisha Rahman", phone: "+60123456789", country: "Malaysia",
            government_id: "9902031z26661zz", date_of_birth: "1985-06-15" }
        ]))
      }

      guest = Booking.order(:id).last.booking_guests.sole.guest
      expect(guest.document_type).not_to eq("malaysian_nric")
      expect(guest.government_id).to eq("9902031z26661zz")
      # Untouched by the IC -- it is only ever derived for a real one.
      expect(guest.date_of_birth).to eq(Date.new(1985, 6, 15))
    end

    it "derives it the same way for a companion sharing the room" do
      post corporate_bookings_path, params: {
        hotel_relationship_id: relationship.id,
        booking: {
          room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
          adults: 2, children: 0, rooms: 1
        }.merge(room_detail([
          { name: "Aisha Rahman", phone: "+60123456789" },
          { name: "Grace Tan", country: "Malaysia", government_id: "900101-14-5523" }
        ]))
      }

      companion = Booking.order(:id).last.booking_guests.find_by!(name_snapshot: "Grace Tan").guest
      expect(companion.date_of_birth).to eq(Date.new(1990, 1, 1))
    end

    # A passport carries no birthdate the way an IC does, so it goes into its
    # own column rather than the one Guest reads as a Malaysian IC.
    it "routes a non-Malaysian's number to passport_number, not government_id" do
      post corporate_bookings_path, params: {
        hotel_relationship_id: relationship.id,
        booking: {
          room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
          adults: 1, children: 0, rooms: 1
        }.merge(room_detail([
          { name: "Priya Singh", phone: "+60123456789", country: "India",
            government_id: "M1234567", date_of_birth: "1990-05-01" }
        ]))
      }

      guest = Booking.order(:id).last.booking_guests.sole.guest
      expect(guest.document_type).to eq("passport")
      expect(guest.passport_number).to eq("m1234567")
      expect(guest.government_id).to be_nil
    end

    # The field's max length gives room for exactly this kind of noise -- a
    # space, a hyphen, a check digit an agent copied straight off the
    # passport's photo page -- rather than forcing them to clean it up first.
    it "strips spaces and hyphens an agent typed around a passport number" do
      post corporate_bookings_path, params: {
        hotel_relationship_id: relationship.id,
        booking: {
          room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
          adults: 1, children: 0, rooms: 1
        }.merge(room_detail([
          { name: "Priya Singh", phone: "+60123456789", country: "India",
            government_id: "M 123-4567", date_of_birth: "1990-05-01" }
        ]))
      }

      guest = Booking.order(:id).last.booking_guests.sole.guest
      expect(guest.passport_number).to eq("m1234567")
    end
  end

  it "saves a companion given a foreign nationality but no date of birth" do
    expect {
      post corporate_bookings_path, params: {
        hotel_relationship_id: relationship.id,
        booking: {
          room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
          adults: 2, children: 0, rooms: 1
        }.merge(room_detail([
          { name: "Aisha Rahman", phone: "+60123456789" },
          { name: "Priya Singh", country: "India" }
        ]))
      }
    }.to change(Booking, :count).by(1)

    booking = Booking.order(:id).last
    companion = booking.booking_guests.find_by!(name_snapshot: "Priya Singh")
    expect(companion.country_snapshot).to eq("India")
    expect(companion.date_of_birth_snapshot).to be_nil
  end

  it "creates a booking when the lead's nationality is foreign and no date of birth was given" do
    expect {
      post corporate_bookings_path, params: {
        hotel_relationship_id: relationship.id,
        booking: {
          room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
          adults: 1, children: 0, rooms: 1
        }.merge(room_detail([ { name: "Priya Singh", phone: "+60123456789", country: "India" } ]))
      }
    }.to change(Booking, :count).by(1)

    expect(response).to have_http_status(:redirect)
    guest = Booking.order(:id).last.primary_guest
    expect(guest.country).to eq("India")
    expect(guest.date_of_birth).to be_nil
  end

  it "leaves nationality blank when the agent does not know it" do
    post corporate_bookings_path, params: {
      hotel_relationship_id: relationship.id,
      booking: {
        room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
        adults: 1, children: 0, rooms: 1
      }.merge(room_detail([ { name: "Aisha Rahman", phone: "+60123456789", country: "" } ]))
    }

    expect(Booking.order(:id).last.guest_country).to be_nil
  end

  # The portal is the agent's own, so a hotel they are not linked to is simply
  # not one of their choices.
  it "refuses to book a hotel this account is not linked to" do
    other = create(:hotel_corporate_account)

    expect {
      post corporate_bookings_path, params: {
        hotel_relationship_id: other.id,
        booking: { room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
                   adults: 2, rooms: 1 }
                 .merge(room_detail([ { name: "Someone", phone: "+60100000000" } ]))
      }
    }.not_to change(Booking, :count)

    expect(response).to redirect_to(new_corporate_booking_path)
  end

  it "books against the sole linked hotel even when the request names none" do
    expect {
      post corporate_bookings_path, params: {
        booking: { room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
                   adults: 2, rooms: 1 }
                 .merge(room_detail([ { name: "Someone", phone: "+60100000000" } ]))
      }
    }.to change(Booking, :count).by(1)

    expect(Booking.order(:id).last.hotel_corporate_account_id).to eq(relationship.id)
  end

  it "shows only this account's bookings" do
    create(:booking, hotel: hotel, hotel_corporate_account: relationship, guest_name: "Mina Corporate")
    create(:booking, hotel: hotel, guest_name: "Theo Walkin")

    get corporate_bookings_path

    expect(response.body).to include("Mina Corporate")
    expect(response.body).not_to include("Theo Walkin")
  end

  # The booking is a wizard: the stay (hotel and dates), the rooms (a cart of lines,
  # each its own category, party and rate), then the guests. Where the agent is,
  # cart included, is in the URL, and a step is never shown ahead of what it needs.
  describe "the booking wizard" do
    let!(:second_room_type) do
      Rooms::SaveSeedRoomType.call!(
        hotel: hotel,
        attributes: { name: "Suite", room_number_mode: "custom", quantity: 2, base_price: 400.0,
                      max_adults: 3, max_children: 2, room_numbers: %w[201 202] }
      )
    end
    let!(:extra_plan) do
      create(:rate_plan, :custom, hotel: hotel, name: "TA Full Board", ta_access: "all").tap do |plan|
        create(:room_type_rate_plan, rate_plan: plan, room_type: room_type, pricing_value: 400)
      end
    end

    def page = Capybara.string(response.body)
    def step = page.find("[data-testid='booking-wizard-steps']")["data-step"]
    # The Deluxe has two rates open to this agent, so a line names one; the Suite has
    # only the corporate rate, which a line may leave unnamed.
    def line(room_type_id:, rate_plan_id: nil, adults: 2, children: 0, quantity: 1)
      rate_plan_id ||= extra_plan.id if room_type_id == room_type.id
      { room_type_id: room_type_id, rate_plan_id: rate_plan_id, adults: adults, children: children, quantity: quantity }.compact
    end
    def rooms_url(lines: nil, **extra)
      new_corporate_booking_path(stay_params({ step: "rooms", lines: lines }.compact.merge(extra)))
    end

    it "starts with the stay: hotel and dates, and nothing about rooms" do
      get new_corporate_booking_path

      expect(step).to eq("stay")
      expect(page).to have_text("Continue to rooms")
      expect(page).to have_no_css("[data-testid='agent-room-types']")
    end

    it "then asks which category, listing no rates and no prices yet" do
      get rooms_url

      expect(step).to eq("rooms")
      expect(page.find("[data-testid='wizard-step-title']")).to have_text("Choose a room category")
      expect(page.all("[data-testid='agent-room-type']").size).to eq(2)
      expect(page).to have_no_css("[data-testid='agent-rates']")
      expect(page).to have_no_text("MYR")
    end

    it "then asks who is in the room" do
      get rooms_url(stage: "occupancy", add_room_type_id: room_type.id)

      expect(page.find("[data-testid='wizard-step-title']")).to have_text("Who is in the Deluxe?")
      expect(page).to have_css("[data-testid='occupancy-step']")
      expect(page).to have_field("add_adults")
      expect(page).to have_field("add_quantity")
    end

    it "then asks for a rate, for that party, in that category alone" do
      get rooms_url(stage: "rate", add_room_type_id: room_type.id, add_adults: 2, add_quantity: 2)

      expect(page.find("[data-testid='wizard-step-title']")).to have_text("Choose a rate")
      expect(page.find("[data-testid='rate-party']")).to have_text("2 rooms").and have_text("Deluxe").and have_text("2 adults")
      expect(page.all("[data-testid='agent-rate']").size).to be >= 2
      expect(page).to have_no_text("Suite")
    end

    it "adds a line to the stay when a rate is chosen, keeping the lines already there" do
      existing = { "0" => line(room_type_id: second_room_type.id, rate_plan_id: second_room_type.rate_plans.first.id, adults: 3) }
      get rooms_url(lines: existing, stage: "rate", add_room_type_id: room_type.id, add_adults: 2, add_quantity: 1)

      href = page.first("[data-testid='select-rate']")[:href]
      query = Rack::Utils.parse_nested_query(URI(href).query)
      expect(query["lines"].keys).to eq(%w[0 1])
      expect(query["lines"]["0"]["room_type_id"]).to eq(second_room_type.id.to_s)
      expect(query["lines"]["1"]).to include("room_type_id" => room_type.id.to_s, "adults" => "2", "quantity" => "1")
      expect(query["lines"]["1"]["rate_plan_id"]).to be_present
    end

    it "shows the cart: every line, its price, the total, and a way to add another room or go on" do
      lines = { "0" => line(room_type_id: room_type.id, adults: 2, quantity: 2), "1" => line(room_type_id: second_room_type.id, adults: 3) }
      get rooms_url(lines: lines)

      cart = page.find("[data-testid='stay-cart']")
      expect(cart.all("[data-testid='cart-line']").size).to eq(2)
      expect(cart).to have_text("2 rooms · Deluxe").and have_text("1 room · Suite").and have_text("3 adults")
      expect(page.find("[data-testid='cart-total']")).to have_text("3 rooms")
      expect(cart).to have_link("Add another room")
      expect(cart).to have_link("Continue to guests")
    end

    it "removes a line from the cart" do
      lines = { "0" => line(room_type_id: room_type.id), "1" => line(room_type_id: second_room_type.id) }
      get rooms_url(lines: lines)

      href = page.find("[data-testid='remove-line-0']")[:href]
      query = Rack::Utils.parse_nested_query(URI(href).query)
      expect(query["lines"].values.map { |entry| entry["room_type_id"] }).to eq([ second_room_type.id.to_s ])
    end

    it "does not offer Continue while a line cannot be booked, and says why" do
      lines = { "0" => line(room_type_id: second_room_type.id, quantity: 3) } # the suite has two rooms
      get rooms_url(lines: lines)

      expect(page.find("[data-testid='cart-line-error']")).to have_text("no longer has")
      expect(page).to have_no_link("Continue to guests")
    end

    it "no longer lists a category once the stay holds all its rooms" do
      lines = { "0" => line(room_type_id: second_room_type.id, quantity: 2) }
      get rooms_url(lines: lines, stage: "category")

      expect(page.all("[data-testid='agent-room-type']").map(&:text).join).to include("Deluxe")
      expect(page.all("[data-testid='agent-room-type']").map(&:text).join).not_to include("Suite")
    end

    it "refuses a party the category cannot hold, and says so" do
      get rooms_url(stage: "rate", add_room_type_id: second_room_type.id, add_adults: 5)

      expect(page.find("[data-testid='wizard-step-title']")).to have_text("Who is in the Suite?")
      expect(page.find("[data-testid='occupancy-error']")).to have_text(second_room_type.occupancy_limit_message)
    end

    it "asks for the guests last: one block per room across every line, each named for its own category and party" do
      lines = { "0" => line(room_type_id: room_type.id, adults: 2, quantity: 2), "1" => line(room_type_id: second_room_type.id, adults: 3) }
      get new_corporate_booking_path(stay_params(step: "guests", lines: lines))

      expect(step).to eq("guests")
      rooms = page.all("[data-testid='guest-room']")
      expect(rooms.size).to eq(3)
      expect(rooms[0]).to have_text("Room 1 · Deluxe")
      expect(rooms[2]).to have_text("Room 3 · Suite").and have_text("3 adults")
      expect(page).to have_css("input[name='booking[rooms_detail][2][guests][2][name]']")
      expect(page).to have_no_css("input[name='booking[rooms_detail][0][guests][2][name]']")
      expect(page).to have_no_css("[data-testid='stay-cart']")
    end

    it "carries every line in the booking form" do
      lines = { "0" => line(room_type_id: room_type.id), "1" => line(room_type_id: second_room_type.id, adults: 3) }
      get new_corporate_booking_path(stay_params(step: "guests", lines: lines))

      expect(page).to have_css("input[name='booking[lines][0][room_type_id]'][value='#{room_type.id}']", visible: :all)
      expect(page).to have_css("input[name='booking[lines][1][adults]'][value='3']", visible: :all)
    end

    it "keeps the stay and the rooms in view, each with a way to change it" do
      get new_corporate_booking_path(stay_params(step: "guests", lines: { "0" => line(room_type_id: room_type.id, quantity: 2) }))

      expect(page.find("[data-testid='summary-stay']")).to have_text(hotel.name).and have_text("2 nights")
      expect(page.find("[data-testid='summary-rooms']")).to have_text("2 rooms").and have_text("2 × Deluxe")
      expect(page.all("[data-testid^='summary-'] a", text: "Change").size).to eq(2)
    end

    it "links the finished steps back with the cart intact" do
      get new_corporate_booking_path(stay_params(step: "guests", lines: { "0" => line(room_type_id: room_type.id) }))

      href = page.find("[data-testid='wizard-step-rooms']")[:href]
      expect(href).to include("step=rooms")
      expect(Rack::Utils.parse_nested_query(URI(href).query)["lines"]["0"]["room_type_id"]).to eq(room_type.id.to_s)
    end

    it "never shows a step ahead of what it needs" do
      get new_corporate_booking_path(stay_params(step: "guests"))

      expect(step).to eq("rooms")
      expect(response.body).not_to include("Guest details")
    end

    it "books the whole stay from the guests step, one booking per room, in one group" do
      lines = { "0" => line(room_type_id: room_type.id, adults: 1, quantity: 1), "1" => line(room_type_id: second_room_type.id, adults: 2) }

      expect {
        post corporate_bookings_path, params: {
          hotel_relationship_id: relationship.id,
          booking: { check_in: check_in.to_s, check_out: check_out.to_s, lines: lines }.merge(
            room_detail([ { name: "Ada Lim", phone: "+60123456789" } ], [ { name: "Bo Tan", phone: "+60127654321" }, { name: "Cy Ong" } ])
          )
        }
      }.to change(Booking, :count).by(2)

      bookings = Booking.order(:id).last(2)
      expect(bookings.map { |booking| booking.booking_rooms.first.room_type }).to eq([ room_type, second_room_type ])
      expect(bookings.map(&:adults)).to eq([ 1, 2 ])
      expect(bookings.map(&:group_booking_id).uniq.compact.size).to eq(1)
    end
  end

  # A multi-room stay is several bookings under one group. Opening one of them
  # leads with that room; the rest of the stay follows beneath it.
  describe "a room that belongs to a multi-room stay" do
    let(:group) { create(:group_booking, hotel: hotel) }
    let!(:rooms) do
      [ [ "Chen Fengping", 1200 ], [ "Law Shunwan", 1200 ], [ "Tse Hanyee", 600 ] ].each_with_index.map do |(name, amount), index|
        create(:booking, hotel: hotel, hotel_corporate_account: relationship, group_booking: group, group_position: index + 1,
                         guest_name: name, adults: 2, total_amount: amount, check_in: check_in, check_out: check_out).tap do |booking|
          guest = create(:guest, name: name, phone: "#{Guest::PHONE_NOT_CAPTURED} RES4757-#{index + 1}")
          create(:booking_guest, booking: booking, guest: guest, is_primary: true)
        end
      end
    end
    let(:opened) { rooms.last }

    it "leads with the room that was opened: its guest, its guests and its own total" do
      get corporate_booking_path(opened)

      page = Capybara.string(response.body)
      expect(page.find("h1")).to have_text("Tse Hanyee")
      header = page.find("dl", match: :first)
      expect(header.text).to match(/MYR\s+600\.00/)
      expect(header).not_to have_text("3000.00")
    end

    it "says the room belongs to a stay, and gives the stay's total" do
      get corporate_booking_path(opened)

      expect(Capybara.string(response.body).find("[data-testid='stay-context']"))
        .to have_text("Part of a 3-room stay").and have_text(/MYR\s+3000\.00/)
    end

    it "gives the opened room its full card and lists the others compactly, each linking to its own page" do
      get corporate_booking_path(opened)

      page = Capybara.string(response.body)
      cards = page.all("[data-testid='agent-room-detail']")
      expect(cards.size).to eq(1)
      expect(cards.first).to have_text("Tse Hanyee")

      expect(page).to have_css("[data-testid='other-rooms-heading']", text: "Other rooms in this stay (2)")
      others = page.all("[data-testid='other-room']")
      expect(others.map { |row| row.text }.join).to include("Chen Fengping", "Law Shunwan")
      expect(others.map { |row| row.find("a", text: "View")[:href] })
        .to contain_exactly(corporate_booking_path(rooms[0]), corporate_booking_path(rooms[1]))
    end

    it "offers to cancel just this room as well as the whole stay" do
      get corporate_booking_path(opened)

      page = Capybara.string(response.body)
      expect(page).to have_link("Cancel whole stay (3 rooms)", href: new_corporate_booking_cancellation_path(opened))
      expect(page).to have_link("Cancel this room", href: new_corporate_booking_cancellation_path(opened, scope: "room"))
    end

    it "says which room of the stay each list row is" do
      get corporate_bookings_path

      expect(response.body).to include("Room 3 of 3", "Room 1 of 3")
    end

    it "does not show an internal placeholder phone number to the agent" do
      get corporate_booking_path(opened)

      expect(response.body).not_to include("NOT CAPTURED")
    end
  end

  it "does not label a single booking as part of a stay" do
    booking = create(:booking, hotel: hotel, hotel_corporate_account: relationship, guest_name: "Solo Guest")

    get corporate_booking_path(booking)

    expect(response.body).not_to include("stay-context", "Other rooms in this stay", "Cancel whole stay")
  end

  describe "the bookings list" do
    it "puts the most recently made booking first" do
      older = travel_to(2.days.ago) { create(:booking, hotel: hotel, hotel_corporate_account: relationship, guest_name: "Older Guest") }
      newer = travel_to(1.hour.ago) { create(:booking, hotel: hotel, hotel_corporate_account: relationship, guest_name: "Newer Guest") }

      get corporate_bookings_path

      expect(response.body.index(newer.guest_name)).to be < response.body.index(older.guest_name)
    end

    it "finds a booking by the guest's name" do
      match = create(:booking, hotel: hotel, hotel_corporate_account: relationship, guest_name: "Zara Aziz")
      other = create(:booking, hotel: hotel, hotel_corporate_account: relationship, guest_name: "Someone Else")

      get corporate_bookings_path(q: "zara")

      expect(response.body).to include(match.guest_name)
      expect(response.body).not_to include(other.guest_name)
    end

    it "filters by status" do
      confirmed = create(:booking, hotel: hotel, hotel_corporate_account: relationship, status: "confirmed", guest_name: "Confirmed Guest")
      cancelled = create(:booking, hotel: hotel, hotel_corporate_account: relationship, status: "cancelled", guest_name: "Cancelled Guest")

      get corporate_bookings_path(status: "cancelled")

      expect(response.body).to include(cancelled.guest_name)
      expect(response.body).not_to include(confirmed.guest_name)
    end

    it "filters to one linked hotel and drops the redundant hotel name from each row once it does" do
      other_hotel = create(:hotel, status: "live")
      other_relationship = create(:hotel_corporate_account, corporate_account: user.account, hotel: other_hotel)
      here = create(:booking, hotel: hotel, hotel_corporate_account: relationship, guest_name: "Here Guest")
      there = create(:booking, hotel: other_hotel, hotel_corporate_account: other_relationship, guest_name: "There Guest")

      get corporate_bookings_path(hotel_relationship_id: relationship.id)

      rows_text = response.parsed_body.css("li").text
      expect(rows_text).to include(here.guest_name)
      expect(rows_text).not_to include(there.guest_name)
      expect(rows_text).not_to include(hotel.name)
    end

    it "shows the hotel name on each row when more than one hotel could appear" do
      other_hotel = create(:hotel, status: "live")
      create(:hotel_corporate_account, corporate_account: user.account, hotel: other_hotel)
      create(:booking, hotel: hotel, hotel_corporate_account: relationship)

      get corporate_bookings_path

      expect(response.body).to include(ERB::Util.html_escape(hotel.name))
    end

    it "paginates at 25 by default and honours a chosen page size" do
      create_list(:booking, 26, hotel: hotel, hotel_corporate_account: relationship)

      get corporate_bookings_path
      expect(response.body.scan(%r{corporate/bookings/\d+"}).size).to eq(25)

      get corporate_bookings_path(per_page: 50)
      expect(response.body.scan(%r{corporate/bookings/\d+"}).size).to eq(26)
    end

    it "falls back to the default page size for an unsupported value" do
      create_list(:booking, 30, hotel: hotel, hotel_corporate_account: relationship)

      get corporate_bookings_path(per_page: 9999)

      expect(response.body.scan(%r{corporate/bookings/\d+"}).size).to eq(25)
    end
  end

  it "records every adult sharing the room, not just the lead" do
    post corporate_bookings_path, params: {
      hotel_relationship_id: relationship.id,
      booking: {
        room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
        adults: 2, children: 0, rooms: 1
      }.merge(room_detail([
        { name: "Aisha Rahman", phone: "+60123456789", email: "aisha@example.com" },
        { name: "Iman Rahman", phone: "+60129876543" }
      ]))
    }

    booking = Booking.order(:id).last
    # The lead is the stay's own guest; the companion is a booking_guest on it,
    # exactly as the desk would add at check-in.
    expect(booking.guest_name).to eq("Aisha Rahman")
    expect(booking.booking_guests.count).to eq(2)
    expect(booking.guests.map(&:name)).to contain_exactly("Aisha Rahman", "Iman Rahman")
    expect(booking.booking_guests.where(is_primary: true).count).to eq(1)
  end

  it "takes the lead guest alone when the companion is not known yet" do
    post corporate_bookings_path, params: {
      hotel_relationship_id: relationship.id,
      booking: {
        room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
        adults: 2, children: 0, rooms: 1
      }.merge(room_detail([
        { name: "Aisha Rahman", phone: "+60123456789" },
        { name: "", phone: "", email: "" }
      ]))
    }

    booking = Booking.order(:id).last
    expect(booking.guest_name).to eq("Aisha Rahman")
    expect(booking.booking_guests.count).to eq(1)
  end

  it "books several rooms as one grouped stay, each with its own guests" do
    expect {
      post corporate_bookings_path, params: {
        hotel_relationship_id: relationship.id,
        booking: {
          room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
          adults: 2, children: 0, rooms: 2
        }.merge(room_detail(
          [ { name: "Aisha Rahman", phone: "+60123456789" }, { name: "Iman Rahman" } ],
          [ { name: "Lee Wei", phone: "+60127654321" }, { name: "Lee Mei" } ]
        ))
      }
    }.to change(Booking, :count).by(2)

    bookings = Booking.order(:id).last(2)
    # One booking is one room -- booking_rooms is unique on booking_id -- so a
    # two-room stay is two bookings under one group.
    expect(bookings.map(&:group_booking_id).uniq.compact.size).to eq(1)
    expect(bookings.map(&:guest_name)).to contain_exactly("Aisha Rahman", "Lee Wei")
    expect(bookings.map { |booking| booking.booking_guests.count }).to eq([ 2, 2 ])
    expect(bookings.map(&:hotel_corporate_account_id).uniq).to eq([ relationship.id ])
  end

  it "refuses the whole party rather than booking half of it" do
    # Four rooms in the category, three already sold: two cannot both be had.
    3.times do
      create(:booking, hotel: hotel, check_in: check_in, check_out: check_out, status: "confirmed").tap do |booking|
        create(:booking_room, booking: booking, room_type: room_type, room_number: nil)
      end
    end

    expect {
      post corporate_bookings_path, params: {
        hotel_relationship_id: relationship.id,
        booking: {
          room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
          adults: 2, rooms: 2
        }.merge(room_detail([ { name: "A", phone: "+60111" } ], [ { name: "B", phone: "+60222" } ]))
      }
    }.not_to change(Booking, :count)

    expect(flash[:alert]).to include("no longer has")
  end

  # The search is not the only gate: a stale page, or two agents confirming the
  # last room at once, both arrive straight at create.
  it "refuses to confirm a category that filled up after the search" do
    4.times do
      create(:booking, hotel: hotel, check_in: check_in, check_out: check_out, status: "confirmed").tap do |booking|
        create(:booking_room, booking: booking, room_type: room_type, room_number: nil)
      end
    end

    expect {
      post corporate_bookings_path, params: {
        hotel_relationship_id: relationship.id,
        booking: { room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
                   adults: 2, rooms: 1 }
                 .merge(room_detail([ { name: "Late Booker", phone: "+60111111111" } ]))
      }
    }.not_to change(Booking, :count)

    expect(flash[:alert]).to include("no longer has")
  end

  it "will not sell a room that is already taken" do
    # One category, four rooms, four already sold for the same nights.
    4.times do
      create(:booking, hotel: hotel, check_in: check_in, check_out: check_out, status: "confirmed").tap do |booking|
        create(:booking_room, booking: booking, room_type: room_type, room_number: nil)
      end
    end

    get new_corporate_booking_path(search_params)

    expect(response.body).to include("free for these dates")
  end

  # The permission gates taking a new room, not seeing the stays already taken:
  # a hotel withdrawing it must not erase an agent's own history with them.
  describe "without the booking permission" do
    let(:relationship) do
      create(:hotel_corporate_account, corporate_account: user.account, hotel: hotel,
                                       agent_booking_enabled: false)
    end

    it "refuses the search form" do
      get new_corporate_booking_path

      expect(response).to redirect_to(corporate_bookings_path)
      expect(flash[:alert]).to include("enabled bookings")
    end

    it "refuses a submitted booking" do
      expect {
        post corporate_bookings_path, params: {
          hotel_relationship_id: relationship.id,
          booking: { room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
                     adults: 2, rooms: 1 }.merge(room_detail([ { first_name: "Ada", last_name: "Lovelace" } ]))
        }
      }.not_to change(Booking, :count)

      expect(response).to redirect_to(corporate_bookings_path)
    end

    it "still lists the stays taken while it was granted, without offering another" do
      get corporate_bookings_path

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("Book a stay")
    end
  end

  # A hotel that only bills this account is not one it can book at, even when
  # another hotel has granted the permission.
  it "keeps a hotel that has not granted the permission out of the picker" do
    billing_only = create(:hotel_corporate_account, corporate_account: user.account,
                                                    hotel: create(:hotel, status: "live", name: "Billing Only Inn"),
                                                    agent_booking_enabled: false)

    get new_corporate_booking_path

    expect(response.body).not_to include("Billing Only Inn")

    post corporate_bookings_path, params: {
      hotel_relationship_id: billing_only.id,
      booking: { room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
                 adults: 2, rooms: 1 }
    }

    expect(response).to redirect_to(new_corporate_booking_path)
  end
end
