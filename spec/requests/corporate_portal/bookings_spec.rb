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

  it "explains the rooms field through an infotip rather than static hint text" do
    get new_corporate_booking_path

    expect(response.body).to include("About rooms")
    expect(response.body).to include("Every room is booked with the same occupancy.")
  end

  it "labels the ID field IC by default, matching the preselected nationality" do
    get new_corporate_booking_path(search_params.merge(room_type_id: room_type.id))

    expect(response.body).to include("agent-guest-identity")
    expect(response.body).to include("IC number")
    expect(response.body).not_to include("IC / Passport")
  end

  it "shows what is available for the dates, priced for the stay" do
    get new_corporate_booking_path(search_params)

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
      get new_corporate_booking_path(search_params)

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
    get new_corporate_booking_path(search_params.merge(room_type_id: room_type.id))

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

  # Guest requires a date of birth for anyone not Malaysian (its own
  # reporting-requirement validation) and the form only offers it once a
  # non-Malaysian nationality is actually picked, so a companion given a
  # foreign nationality with no date of birth is dropped rather than saved
  # half-answered -- the same "log, don't fail the booking" the phone and
  # email fields already get.
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
    # own column rather than the one Guest reads as a Malaysian IC -- and the
    # date of birth genuinely has to be typed for this guest.
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

  it "quietly skips a companion given a foreign nationality but no date of birth" do
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
    expect(booking.booking_guests.exists?(name_snapshot: "Priya Singh")).to be(false)
  end

  # The one case that must never silently break: a lead guest given a foreign
  # nationality but no date of birth cannot become a Guest record at all
  # (Guest's own validation), and CreateManualBooking's guest step is not
  # optional the way a companion's is -- so this has to fail the whole booking
  # cleanly, with a message, rather than losing the room to an unhandled error.
  it "refuses cleanly when the lead's nationality is foreign and no date of birth was given" do
    expect {
      post corporate_bookings_path, params: {
        hotel_relationship_id: relationship.id,
        booking: {
          room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
          adults: 1, children: 0, rooms: 1
        }.merge(room_detail([ { name: "Priya Singh", phone: "+60123456789", country: "India" } ]))
      }
    }.not_to change(Booking, :count)

    expect(response).to have_http_status(:redirect)
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
    mine = create(:booking, hotel: hotel, hotel_corporate_account: relationship)
    theirs = create(:booking, hotel: hotel)

    get corporate_bookings_path

    expect(response.body).to include(mine.guest_name)
    expect(response.body).not_to include(theirs.guest_name)
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
