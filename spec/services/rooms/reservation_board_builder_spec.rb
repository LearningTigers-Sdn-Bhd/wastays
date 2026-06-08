# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::ReservationBoardBuilder do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_numbers: [ "101" ]) }
  let(:start_date) { Date.current }
  let(:builder) { described_class.new(hotel: hotel, start_date: start_date, days: 7) }

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
  end
end
