# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporatePortal::CreateAgentBooking do
  let(:user) { create(:user, :corporate) }
  let(:hotel) { create(:hotel, status: "live") }
  let(:relationship) { create(:hotel_corporate_account, corporate_account: user.account, hotel: hotel, account_type: "travel_agent") }

  let!(:room_type) do
    Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "Deluxe", room_number_mode: "custom", quantity: 4, base_price: 250.0,
                    max_adults: 3, max_children: 2, room_numbers: %w[101 102 103 104] }
    )
  end

  let(:check_in) { Date.current + 14 }
  let(:check_out) { Date.current + 16 }

  def params(rooms_detail, overrides = {})
    {
      room_type_id: room_type.id,
      check_in: check_in.to_s,
      check_out: check_out.to_s,
      adults: 2,
      children: 0,
      rooms: rooms_detail.size,
      rooms_detail: rooms_detail.each_with_index.to_h { |guests, index|
        [ index.to_s, { guests: guests.each_with_index.to_h { |attrs, i| [ i.to_s, attrs ] } } ]
      }
    }.merge(overrides)
  end

  def call(rooms_detail, overrides = {}, actor: user)
    described_class.call(relationship: relationship, params: params(rooms_detail, overrides), user: actor)
  end

  it "books a room and attributes it to the agency" do
    result = call([ [ { name: "Ada Lim", phone: "+60123456789" } ] ])

    expect(result).to be_success
    expect(result.booking.hotel_corporate_account_id).to eq(relationship.id)
    expect(result.booking.guest_name).to eq("Ada Lim")
  end

  # "internal" would be indistinguishable from a booking keyed at the desk, so
  # agent sales would not show up in any source-grouped report.
  it "records the booking against the travel agent source" do
    result = call([ [ { name: "Ada Lim", phone: "+60123456789" } ] ])

    expect(result.booking.source).to eq("travel_agent")
    expect(BookingSource.find_by_source("travel_agent")).to be_present
  end

  # The agency is already known from the relationship; who at the agency made
  # the booking is not recorded anywhere else and cannot be reconstructed later.
  it "records which person at the agency made the booking, and when" do
    freeze_time do
      result = call([ [ { name: "Ada Lim", phone: "+60123456789" } ] ])

      expect(result.booking.corporate_booked_by).to eq(user)
      expect(result.booking.corporate_booked_at).to eq(Time.current)
    end
  end

  it "records the acting person on every room of a multi-room booking" do
    result = call([
      [ { name: "Ada Lim", phone: "+60123456789" } ],
      [ { name: "Grace Tan", phone: "+60123456780" } ]
    ])

    expect(result).to be_success
    expect(result.bookings.size).to eq(2)
    expect(result.bookings.map(&:corporate_booked_by_id).uniq).to eq([ user.id ])
    expect(result.bookings.map(&:corporate_booked_at)).to all(be_present)
  end

  it "still books when there is no acting user to record" do
    result = call([ [ { name: "Ada Lim", phone: "+60123456789" } ] ], {}, actor: nil)

    expect(result).to be_success
    expect(result.booking.corporate_booked_by_id).to be_nil
    expect(result.booking.corporate_booked_at).to be_present
  end

  # The deadline is what the sweeper enforces, so it has to be stamped when the
  # booking is taken rather than derived later.
  describe "the payment deadline" do
    it "stamps a standard account's booking with a deadline" do
      freeze_time do
        result = call([ [ { name: "Ada Lim", phone: "+60123456789" } ] ])

        expect(result.booking.payment_due_at).to eq(Time.current + 48.hours)
      end
    end

    it "uses the agency's own hold when it has one" do
      relationship.update!(agent_payment_hold_hours: 6)

      freeze_time do
        result = call([ [ { name: "Ada Lim", phone: "+60123456789" } ] ])

        expect(result.booking.payment_due_at).to eq(Time.current + 6.hours)
      end
    end

    it "leaves a direct-bill account's booking without one" do
      relationship.update!(relationship_type: "direct_bill")

      result = call([ [ { name: "Ada Lim", phone: "+60123456789" } ] ])

      expect(result.booking.payment_due_at).to be_nil
    end

    # The reported case: an agent selling a room for this afternoon, after the
    # desk has started checking guests in. The arrival floor used to stamp a
    # deadline in the past, and Bookings::ReleaseUnpaidAgentBookings cancelled
    # the booking on its next pass -- within five minutes, with the agent never
    # having had a chance to pay.
    it "still gives an agent time on a booking taken after today's check-in time" do
      relationship.update!(agent_payment_hold_hours: 1)
      arrival = Bookings::ScheduledStay.at_hotel_time(hotel: hotel, value: Date.current, kind: :check_in)

      travel_to(arrival + 1.hour) do
        result = call(
          [ [ { name: "Ada Lim", phone: "+60123456789" } ] ],
          { check_in: Date.current.to_s, check_out: (Date.current + 2).to_s }
        )

        expect(result).to be_success
        expect(result.booking.payment_due_at).to eq(Time.current + 30.minutes)
        expect(result.booking.payment_due_at).to be > Time.current
      end
    end

    it "stamps every room of a multi-room booking" do
      result = call([
        [ { name: "Ada Lim", phone: "+60123456789" } ],
        [ { name: "Grace Tan", phone: "+60123456780" } ]
      ])

      expect(result.bookings.map(&:payment_due_at)).to all(be_present)
    end
  end

  it "refuses without a room category" do
    result = call([ [ { name: "Ada Lim", phone: "+60123456789" } ] ], { room_type_id: nil })

    expect(result).not_to be_success
    expect(result.errors).to include("Choose a room category.")
  end

  it "refuses when no room has a named lead guest" do
    result = call([ [ { name: "", phone: "" } ] ])

    expect(result).not_to be_success
    expect(result.errors).to include("Name the lead guest for each room.")
  end
end
