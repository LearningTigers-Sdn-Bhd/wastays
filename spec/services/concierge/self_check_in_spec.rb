require "rails_helper"

RSpec.describe Concierge::SelfCheckIn, frozen_time: Time.zone.local(2026, 6, 10, 3) do
  let(:hotel) { create(:hotel, status: "live") }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:booking) do
    b = create(:booking, hotel: hotel, status: "confirmed", check_in: Date.today, check_out: Date.today + 1)
    b.booking_rooms.create!(room_type: room_type, subtotal: 200,
                             room_type_snapshot: { "name" => room_type.name })
    b
  end

  def with_available_room(room_number: "101", date: Date.today)
    numbers = (room_type.room_numbers + [ room_number ]).uniq
    renumber_room_type!(room_type, numbers, room_number_mode: "custom")
    create(:room_inventory, room_type: room_type, date: date,
           quantity: 1, status: "open", available_room_numbers: [ room_number ])
    room_number
  end

  def call(latitude: nil, longitude: nil)
    described_class.new(booking: booking, latitude: latitude, longitude: longitude).call
  end

  before { BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current) }

  context "when everything is ready" do
    before { with_available_room }

    it "delegates check-in lifecycle processing with the selected room" do
      processor = instance_double(Bookings::ProcessCheckIn, call: OpenStruct.new(success?: true))
      allow(Bookings::ProcessCheckIn).to receive(:new).and_return(processor)

      result = call

      expect(Bookings::ProcessCheckIn).to have_received(:new).with(
        bookings: [ booking ],
        details: {
          checked_in_at: Time.current.in_time_zone(hotel.hotel_time_zone),
          room_assignments: { booking.booking_rooms.first.id.to_s => "101" }
        },
        user: nil,
        source: "concierge_page"
      )
      expect(result.success?).to be true
      expect(result.room_number).to eq("101")
    end

    it "returns the lifecycle processor failure unchanged" do
      processor = instance_double(
        Bookings::ProcessCheckIn,
        call: OpenStruct.new(success?: false, error: "Check-in lifecycle failed")
      )
      allow(Bookings::ProcessCheckIn).to receive(:new).and_return(processor)

      result = call

      expect(result.success?).to be false
      expect(result.error_code).to eq(:error)
      expect(result.message).to eq("Check-in lifecycle failed")
    end

    it "classifies a closed check-in date without exposing the accounting error" do
      hotel.current_business_date_record.update!(status: "closed")

      result = call

      expect(result.success?).to be false
      expect(result.error_code).to eq(:closed_check_in_date)
      expect(result.message).to be_nil
    end

    it "classifies a business date closed during lifecycle processing" do
      lifecycle_called = false
      processor = instance_double(Bookings::ProcessCheckIn)
      allow(processor).to receive(:call) do
        lifecycle_called = true
        OpenStruct.new(success?: false, error: "Reason required for backdated check-in on closed date 2026-07-23.")
      end
      allow(Bookings::ProcessCheckIn).to receive(:new).and_return(processor)
      allow(hotel).to receive(:date_closed?) { lifecycle_called }

      result = call

      expect(result.success?).to be false
      expect(result.error_code).to eq(:closed_check_in_date)
      expect(result.message).to be_nil
    end

    it "returns a fallback message when lifecycle processing fails without an error" do
      processor = instance_double(
        Bookings::ProcessCheckIn,
        call: OpenStruct.new(success?: false, error: nil)
      )
      allow(Bookings::ProcessCheckIn).to receive(:new).and_return(processor)

      result = call

      expect(result.success?).to be false
      expect(result.error_code).to eq(:error)
      expect(result.message).to eq("Check-in lifecycle failed.")
    end

    it "rolls back canonical lifecycle writes when folio initialization fails" do
      allow(Folios::Lifecycle::InitializeForBooking).to receive(:call).and_raise("Folio initialization failed")

      result = call

      expect(result.success?).to be false
      expect(result.message).to eq("Folio initialization failed")
      expect(booking.reload.status).to eq("confirmed")
      expect(booking.booking_rooms.first.reload.room_number).to be_nil
      expect(booking.booking_folio).to be_nil
      expect(BookingAuditLog.where(auditable: booking, action_type: "check_in")).not_to exist
    end

    it "checks in the booking" do
      result = call
      expect(result.success?).to be true
      expect(booking.reload.status).to eq("checked_in")
    end

    it "assigns the room number" do
      result = call
      expect(result.room_number).to eq("101")
      expect(booking.booking_rooms.first.reload.room_number).to eq("101")
    end

    it "records concierge lifecycle audit metadata" do
      call

      audit = BookingAuditLog.find_by!(auditable: booking, action_type: "check_in")
      expect(audit.source).to eq("concierge_page")
      expect(audit.user_id).to be_nil
      expect(audit.metadata["room_number"]).to eq("101")
    end
  end

  context "wrong date" do
    let(:booking) do
      b = create(:booking, hotel: hotel, status: "confirmed",
                 check_in: Date.tomorrow, check_out: Date.tomorrow + 1)
      b.booking_rooms.create!(room_type: room_type, subtotal: 200,
                               room_type_snapshot: { "name" => room_type.name })
      b
    end

    it "returns :wrong_date" do
      result = call
      expect(result.success?).to be false
      expect(result.error_code).to eq(:wrong_date)
    end
  end

  context "too early" do
    before do
      future_time = (Time.current.in_time_zone(hotel.hotel_time_zone) + 2.hours).strftime("%H:%M")
      hotel.create_property_policy!(check_in_time: future_time, check_out_time: "12:00",
                                    currency: "MYR") unless hotel.property_policy
      hotel.property_policy.update!(check_in_time: future_time)
      with_available_room
    end

    it "returns :too_early" do
      result = call
      expect(result.success?).to be false
      expect(result.error_code).to eq(:too_early)
    end
  end

  context "updated check-in policy (e.g. 14:00) after booking creation with default (e.g. 15:00)" do
    before do
      travel 11.hours + 25.minutes
      hotel.create_property_policy!(check_in_time: "14:00", check_out_time: "12:00",
                                    currency: "MYR") unless hotel.property_policy
      hotel.property_policy.update!(check_in_time: "14:00")
      booking.update_columns(check_in: Time.zone.local(2026, 6, 10, 15, 0, 0))
      with_available_room
    end

    after do
      travel_back
    end

    it "allows check-in at 14:25 because it is past the 14:00 policy check-in time" do
      result = call
      expect(result.success?).to be true
      expect(booking.reload.status).to eq("checked_in")
    end
  end

  context "no room available" do
    it "returns :no_room_available when no inventory" do
      result = call
      expect(result.error_code).to eq(:no_room_available)
    end

    it "returns :no_room_available when available_room_numbers is empty" do
      create(:room_inventory, room_type: room_type, date: Date.today,
             quantity: 1, status: "open", available_room_numbers: [])
      result = call
      expect(result.error_code).to eq(:no_room_available)
    end

    it "returns :no_room_available when all rooms are not ready" do
      with_available_room(room_number: "101")
      RoomStatus.create!(hotel: hotel, room_type: room_type, room_number: "101", status: "dirty")
      result = call
      expect(result.error_code).to eq(:no_room_available)
    end
  end

  context "late arrival (past check_in date)" do
    let(:booking) do
      b = create(:booking, hotel: hotel, status: "confirmed",
                 check_in: Date.yesterday, check_out: Date.today)
      b.booking_rooms.create!(room_type: room_type, subtotal: 200,
                               room_type_snapshot: { "name" => room_type.name })
      b
    end

    before { with_available_room(date: Date.yesterday) }

    it "classifies a missing arrival accounting date as closed" do
      result = call
      expect(result.success?).to be false
      expect(result.error_code).to eq(:closed_check_in_date)
    end
  end

  context "no check_in_time configured" do
    before do
      hotel.property_policy&.update!(check_in_time: nil)
      with_available_room
    end

    it "skips time check and allows check-in" do
      result = call
      expect(result.success?).to be true
    end
  end

  context "when a room is occupied by another active booking" do
    before do
      with_available_room(room_number: "101")

      other = create(:booking, hotel: hotel, status: "checked_in",
                     check_in: Date.today, check_out: Date.today + 1)
      other.booking_rooms.create!(room_type: room_type, subtotal: 200,
                                  room_number: "101",
                                  room_type_snapshot: { "name" => room_type.name })
    end

    it "does not assign that room to this booking" do
      result = call
      expect(result.error_code).to eq(:no_room_available)
    end
  end

  context "when several rooms are available" do
    before do
      renumber_room_type!(room_type, %w[105 101 110], room_number_mode: "custom")
      create(:room_inventory, room_type: room_type, date: Date.today,
             quantity: 3, status: "open", available_room_numbers: %w[105 101 110])
    end

    it "picks the lowest room number" do
      result = call
      expect(result.success?).to be true
      expect(result.room_number).to eq("101")
    end
  end

  context "when geolocation check is required" do
    before do
      hotel.update!(google_map_link: "https://www.google.com/maps/place/Sample+Hotel/@5.9771228,116.0622732,15z")
      with_available_room
    end

    it "returns :missing_location if no coordinates are passed" do
      result = call
      expect(result.success?).to be false
      expect(result.error_code).to eq(:missing_location)
    end

    it "returns :too_far_away if coordinates are far from the hotel" do
      # Coordinates for Kuala Lumpur (approx 1600km from KK)
      result = call(latitude: 3.1390, longitude: 101.6869)
      expect(result.success?).to be false
      expect(result.error_code).to eq(:too_far_away)
    end

    it "allows check-in if coordinates are close to the hotel" do
      # Coordinates very close (within 50m of 5.9771228, 116.0622732)
      result = call(latitude: 5.9772, longitude: 116.0623)
      expect(result.success?).to be true
      expect(booking.reload.status).to eq("checked_in")
    end
  end

  context "when geolocation check is skipped (no coordinates configured on hotel)" do
    before do
      hotel.update!(google_map_link: nil)
      with_available_room
    end

    it "allows check-in without coordinates" do
      result = call
      expect(result.success?).to be true
      expect(booking.reload.status).to eq("checked_in")
    end
  end

  context "when geolocation check is disabled in hotel settings" do
    before do
      hotel.update!(geolocation_enabled: false, google_map_link: "https://www.google.com/maps/place/Sample+Hotel/@5.9771228,116.0622732,15z")
      with_available_room
    end

    it "skips location check and allows check-in even without coordinates" do
      result = call
      expect(result.success?).to be true
      expect(booking.reload.status).to eq("checked_in")
    end
  end
end
