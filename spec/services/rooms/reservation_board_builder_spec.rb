# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::ReservationBoardBuilder do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_numbers: [ "101" ]) }
  let(:start_date) { Date.current }
  let(:builder) { described_class.new(hotel: hotel, start_date: start_date, days: 7) }

  def count_sql_queries
    queries = []
    callback = lambda do |_name, _started, _finished, _unique_id, payload|
      next if payload[:cached]
      next if %w[SCHEMA TRANSACTION].include?(payload[:name])

      queries << payload[:sql]
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries.count
  end

  describe "#call" do
    context "when a room is out_of_service or inspection_failed" do
      let!(:room_status) { create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "inspection_failed") }

      it "spans the entire visible row" do
        result = builder.call
        room_group = result[:room_groups].find { |g| g[:room_type] == room_type }
        room = room_group[:rooms].find { |r| r[:room_number] == "101" }
        status_block = room[:blocks].find { |b| b[:type] == "room_status" }

        expect(status_block[:check_in]).to eq(start_date)
        expect(status_block[:check_out]).to eq(start_date + 7.days)
        expect(status_block[:span]).to eq(7)
      end
    end

    context "when a room is dirty" do
      let!(:room_status) { create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty") }

      it "only spans 1 day" do
        result = builder.call
        room_group = result[:room_groups].find { |g| g[:room_type] == room_type }
        room = room_group[:rooms].find { |r| r[:room_number] == "101" }
        status_block = room[:blocks].find { |b| b[:type] == "room_status" }

        expect(status_block[:span]).to eq(1)
        expect(status_block[:check_out]).to eq(Date.current + 1.day)
      end

      context "with an overlapping active booking" do
        let!(:booking) { create(:booking, hotel: hotel, check_in: Date.current - 1.day, check_out: Date.current + 2.days) }

        before do
          create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
        end

        it "starts on the guest checkout day" do
          result = builder.call
          room_group = result[:room_groups].find { |g| g[:room_type] == room_type }
          room = room_group[:rooms].find { |r| r[:room_number] == "101" }
          status_block = room[:blocks].find { |b| b[:type] == "room_status" }

          # If today is 12th and checkout is 14th, it should start on 14th
          expect(status_block[:check_in]).to eq(booking.check_out)
          expect(status_block[:span]).to eq(1)
          expect(status_block[:start_offset]).to eq(2)
        end
      end

      context "with no upcoming bookings" do
        it "only spans 1 day" do
          result = builder.call
          room_group = result[:room_groups].find { |g| g[:room_type] == room_type }
          room = room_group[:rooms].find { |r| r[:room_number] == "101" }
          status_block = room[:blocks].find { |b| b[:type] == "room_status" }

          expect(status_block[:check_out]).to eq(Date.current + 1.day)
          expect(status_block[:span]).to eq(1)
        end
      end
    end

    it "keeps SQL query count bounded as rooms, bookings, and notes grow" do
      small_hotel = create_board_fixture(room_count: 1)
      large_hotel = create_board_fixture(room_count: 6)

      small_count = count_sql_queries { described_class.new(hotel: small_hotel, start_date: start_date, days: 7).call }
      large_count = count_sql_queries { described_class.new(hotel: large_hotel, start_date: start_date, days: 7).call }

      expect(large_count).to be <= small_count + 1
    end
  end

  def create_board_fixture(room_count:)
    current_hotel = create(:hotel)
    room_numbers = room_count.times.map { |index| (200 + index).to_s }
    current_room_type = create(:room_type, hotel: current_hotel, room_number_mode: "custom", room_numbers: room_numbers)

    room_numbers.each do |room_number|
      create(:room_status, hotel: current_hotel, room_type: current_room_type, room_number: room_number, status: "dirty")
      booking = create(:booking, hotel: current_hotel, check_in: start_date, check_out: start_date + 2.days)
      create(:booking_room, booking: booking, room_type: current_room_type, room_number: room_number)
      create(:booking_note, booking: booking)
    end

    current_hotel
  end
end
