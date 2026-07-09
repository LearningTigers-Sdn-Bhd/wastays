require "rails_helper"

RSpec.describe HotelPortal::Requests::StatusUpdater do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }

  it "marks housekeeping as completed" do
    request = create(:housekeeping_request, booking: booking, status: "pending")
    result = described_class.new(hotel: hotel, kind: :housekeeping, request_id: request.id, status: :completed).call

    expect(result).to eq(request)
    expect(request.reload.status).to eq("completed")
    expect(request.completed_at).to be_present
  end

  it "maps complaint completed to resolved" do
    request = create(:complaint_request, booking: booking, status: "pending")
    result = described_class.new(hotel: hotel, kind: :complaint, request_id: request.id, status: :completed).call

    expect(result).to eq(request)
    expect(request.reload.status).to eq("resolved")
  end

  it "marks room as cleaning when housekeeping request is dispatched" do
    room_type = create(:room_type, hotel: hotel, room_numbers: [ "101" ])
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
    request = create(:housekeeping_request, booking: booking, status: "pending")

    described_class.new(hotel: hotel, kind: :housekeeping, request_id: request.id, status: :in_progress).call

    room_status = RoomStatus.find_by(hotel: hotel, room_number: "101")
    expect(room_status.status).to eq("cleaning")
  end

  it "marks room as ready when housekeeping request is completed" do
    room_type = create(:room_type, hotel: hotel, room_numbers: [ "101" ])
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
    
    room_status = RoomStatus.find_or_create_by!(hotel: hotel, room_type: room_type, room_number: "101")
    room_status.update!(status: "cleaning")
    
    request = create(:housekeeping_request, booking: booking, status: "in_progress", room_number: "101", request_details: "Clean the sheets")

    described_class.new(hotel: hotel, kind: :housekeeping, request_id: request.id, status: :completed).call

    expect(room_status.reload.status).to eq("ready")
  end
end
