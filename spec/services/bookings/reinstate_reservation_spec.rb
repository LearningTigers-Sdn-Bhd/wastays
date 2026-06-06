# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::ReinstateReservation, type: :service do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:check_in) { 1.day.ago.to_date }
  let(:check_out) { 2.days.from_now.to_date }
  let(:room_type) { create(:room_type, hotel: hotel, base_price: 200, room_numbers: %w[101 102]) }
  let(:booking) { create(:booking, hotel: hotel, status: "no_show", check_in: check_in, check_out: check_out) }
  let!(:booking_room) { create(:booking_room, booking: booking, room_type: room_type, room_number: "101", subtotal: 600) }
  let(:params) { { booking_rooms_attributes: [ { id: booking_room.id, room_number: "101" } ] } }
  let(:options) { { reason: "Guest arrived late" } }

  subject { described_class.new(booking: booking, params: params, user: user, options: options) }

  before do
    allow(Folios::ProcessCatchUpCharges).to receive(:call)
    allow(Folios::InitializeForBooking).to receive(:call)
    allow(Bookings::RecordAuditLog).to receive(:call)
  end

  context "when successful" do
    it "transitions booking to checked_in" do
      result = subject.call
      expect(result.success?).to be true
      expect(booking.reload.status).to eq("checked_in")
      expect(booking.checked_in_at).to be_present
    end

    it "calls Folios::ProcessCatchUpCharges with is_reinstate: true" do
      subject.call
      expect(Folios::ProcessCatchUpCharges).to have_received(:call).with(
        booking: booking,
        user: user,
        is_reinstate: true
      )
    end

    it "updates room numbers if params are provided" do
      params[:booking_rooms_attributes][0][:room_number] = "102"
      subject.call
      expect(booking_room.reload.room_number).to eq("102")
    end

    it "updates room category, selected rate, subtotal, and booking total" do
      new_room_type = create(:room_type, hotel: hotel, base_price: 250, room_numbers: %w[201 202])
      rate_plan = create(:rate_plan, room_type: new_room_type)
      params[:booking_rooms_attributes][0].merge!(
        room_type_id: new_room_type.id,
        room_number: "201",
        rate_plan_id: rate_plan.id
      )

      result = subject.call

      expect(result.success?).to be true
      expect(booking_room.reload.room_type).to eq(new_room_type)
      expect(booking_room.rate_plan).to eq(rate_plan)
      expect(booking_room.room_number).to eq("201")
      expect(booking_room.subtotal).to eq(750)
      expect(booking.reload.total_amount).to eq(750)
      expect(booking.hotel_snapshot["room_number"]).to eq("201")
    end

    it "returns failure when the selected rate does not belong to the selected room category" do
      other_room_type = create(:room_type, hotel: hotel, base_price: 250, room_numbers: %w[201])
      other_rate_plan = create(:rate_plan, room_type: other_room_type)
      params[:booking_rooms_attributes][0].merge!(rate_plan_id: other_rate_plan.id)

      result = subject.call

      expect(result.success?).to be false
      expect(result.error).to include("Selected rate is not available")
    end

    it "keeps the existing rate when the submitted rate is blank for the same room category" do
      rate_plan = create(:rate_plan, room_type: room_type)
      booking_room.update!(rate_plan: rate_plan)
      params[:booking_rooms_attributes][0].merge!(room_type_id: room_type.id, rate_plan_id: "")

      result = subject.call

      expect(result.success?).to be true
      expect(booking_room.reload.rate_plan).to eq(rate_plan)
    end

    it "reserves inventory for the remaining stay" do
      inventory_manager = instance_double(Bookings::InventoryManager)
      allow(Bookings::InventoryManager).to receive(:new).with(booking).and_return(inventory_manager)
      allow(inventory_manager).to receive(:reserve_by_dates)

      subject.call

      business_date = hotel.business_date_for(Time.current)
      expect(inventory_manager).to have_received(:reserve_by_dates).with(business_date, booking.check_out)
    end
  end

  context "when room is not available" do
    before do
      other_booking = create(:booking, hotel: hotel, status: "confirmed", check_in: check_in, check_out: check_out)
      create(:booking_room, booking: other_booking, room_type: room_type, room_number: "101")
    end

    it "returns failure" do
      result = subject.call
      expect(result.success?).to be false
      expect(result.error).to include("not available")
    end

    it "does not persist room or pricing changes" do
      new_room_type = create(:room_type, hotel: hotel, base_price: 250, room_numbers: %w[201])
      other_booking = create(:booking, hotel: hotel, status: "confirmed", check_in: check_in, check_out: check_out)
      create(:booking_room, booking: other_booking, room_type: new_room_type, room_number: "201")
      params[:booking_rooms_attributes][0].merge!(room_type_id: new_room_type.id, room_number: "201")
      original_total = booking.total_amount

      result = subject.call

      expect(result.success?).to be false
      expect(booking_room.reload.room_type).to eq(room_type)
      expect(booking_room.room_number).to eq("101")
      expect(booking.reload.total_amount).to eq(original_total)
    end
  end

  context "when booking is not a no-show" do
    let(:booking) { create(:booking, hotel: hotel, status: "confirmed") }

    it "returns failure" do
      result = subject.call
      expect(result.success?).to be false
      expect(result.error).to eq("Only no-show bookings can be reinstated.")
    end
  end
end
