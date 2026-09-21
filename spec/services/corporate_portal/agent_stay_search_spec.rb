# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporatePortal::AgentStaySearch do
  let(:hotel) { create(:hotel, status: "live") }

  let!(:room_type) do
    Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "Deluxe", room_number_mode: "custom", quantity: 4, base_price: 250.0,
                    max_adults: 3, max_children: 2, room_numbers: %w[101 102 103 104] }
    )
  end

  let(:check_in) { Date.current + 14 }
  let(:check_out) { Date.current + 16 }

  def search(overrides = {})
    described_class.call(**{ hotel: hotel, check_in: check_in, check_out: check_out, adults: 2 }.merge(overrides))
  end

  def option_for(result, type = room_type)
    result.options.find { |candidate| candidate.room_type.id == type.id }
  end

  # A stay holds a room over its dates whether or not a room number has been
  # assigned, which is the whole reason this counts capacity rather than
  # reading free room numbers.
  def occupy(count, status: "confirmed")
    count.times do
      booking = create(:booking, hotel: hotel, check_in: check_in, check_out: check_out, status: status)
      create(:booking_room, booking: booking, room_type: room_type)
    end
  end

  describe "validation" do
    it "refuses a stay with no dates" do
      expect(search(check_in: nil).error).to eq("Choose an arrival and a departure date.")
    end

    it "refuses a departure on or before arrival" do
      expect(search(check_out: check_in).error).to eq("Departure must be after arrival.")
      expect(search(check_out: check_in - 1).error).to eq("Departure must be after arrival.")
    end

    it "refuses an arrival in the past" do
      expect(search(check_in: Date.current - 1, check_out: Date.current + 1).error)
        .to eq("Arrival cannot be in the past.")
    end

    it "accepts the dates as strings, as the search form sends them" do
      result = search(check_in: check_in.to_s, check_out: check_out.to_s)

      expect(result).to be_success
      expect(result.nights).to eq(2)
    end
  end

  describe "availability" do
    it "counts every configured room when nothing overlaps" do
      expect(option_for(search).available_count).to eq(4)
    end

    # An unassigned reservation still consumes a room in the category; the
    # agent cannot see room numbers to judge for themselves.
    it "counts unassigned reservations against capacity" do
      occupy(3)

      expect(option_for(search).available_count).to eq(1)
    end

    it "ignores stays that do not overlap the dates" do
      booking = create(:booking, hotel: hotel, check_in: check_in + 10, check_out: check_out + 10)
      create(:booking_room, booking: booking, room_type: room_type)

      expect(option_for(search).available_count).to eq(4)
    end

    it "ignores cancelled stays" do
      occupy(2, status: "cancelled")

      expect(option_for(search).available_count).to eq(4)
    end

    it "never reports negative capacity" do
      occupy(4)

      expect(option_for(search).available_count).to eq(0)
    end
  end

  describe "an option" do
    it "is available only when the whole request fits" do
      occupy(2)
      result = search(rooms: 3)

      expect(option_for(result).available_count).to eq(2)
      expect(option_for(result)).not_to be_available
      expect(result.available).to be_empty
    end

    it "is available when exactly enough rooms remain" do
      occupy(2)

      expect(option_for(search(rooms: 2))).to be_available
    end

    it "prices each room once and multiplies by the rooms asked for" do
      option = option_for(search(rooms: 3))

      expect(option.per_room_amount).to be_present
      expect(option.total_amount).to eq(option.per_room_amount * 3)
    end

    it "quotes in the hotel's currency" do
      expect(option_for(search).currency).to eq(hotel.default_currency.presence || "MYR")
    end
  end

  it "leaves out a category that cannot hold the party" do
    expect(option_for(search(adults: 9))).to be_nil
  end

  it "treats a request for no rooms as a request for one" do
    expect(search(rooms: 0).rooms).to eq(1)
  end
end
