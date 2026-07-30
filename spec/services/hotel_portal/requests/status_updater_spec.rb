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

  it "updates housekeeping request successfully even if booking is nil but hotel matches" do
    request = create(:housekeeping_request, booking: nil, hotel: hotel, status: "pending")
    result = described_class.new(hotel: hotel, kind: :housekeeping, request_id: request.id, status: :completed).call

    expect(result).to eq(request)
    expect(request.reload.status).to eq("completed")
  end

  it "maps checkout workflow statuses onto checkout requests" do
    request = create(:check_out_request, booking: booking, status: "pending")

    result = described_class.new(hotel: hotel, kind: :checkout, request_id: request.id, status: :assigned).call

    expect(result).to eq(request)
    expect(request.reload.status).to eq("assigned")
    expect(request.metadata["workflow_status"]).to eq("assigned")

    described_class.new(hotel: hotel, kind: :checkout, request_id: request.id, status: :completed).call
    expect(request.reload.status).to eq("completed")
    expect(request.metadata["workflow_status"]).to eq("completed")
  end

  it "marks the checkout room as cleaning when checkout work starts" do
    room_type = create(:room_type, hotel: hotel, room_numbers: [ "101" ])
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
    request = create(
      :check_out_request,
      booking: booking,
      status: "new",
      guest_notes: "Checkout Room Cleaning",
      metadata: { "room_number" => "101" }
    )

    described_class.new(hotel: hotel, kind: :checkout, request_id: request.id, status: :in_progress).call

    expect(RoomStatus.find_by(hotel: hotel, room_type: room_type, room_number: "101").status).to eq("cleaning")
  end
  # A checkout used to keep no record of when it finished, so the board stood
  # updated_at in for it -- and updated_at moves on any write.
  describe "recording when a checkout finished" do
    let(:checkout) { create(:check_out_request, booking: booking, status: "new", completed_at: nil) }

    it "sets completed_at when it completes" do
      freeze_time do
        described_class.new(hotel: hotel, kind: :checkout, request_id: checkout.id, status: "completed").call

        expect(checkout.reload.completed_at).to eq(Time.current)
      end
    end

    it "leaves an already recorded finish where it is" do
      finished_at = 3.days.ago.change(usec: 0)
      checkout.update!(status: "completed", completed_at: finished_at)

      described_class.new(hotel: hotel, kind: :checkout, request_id: checkout.id, status: "completed").call

      expect(checkout.reload.completed_at).to eq(finished_at)
    end

    it "clears it when the checkout is moved back to open work" do
      checkout.update!(status: "completed", completed_at: 1.day.ago)

      described_class.new(hotel: hotel, kind: :checkout, request_id: checkout.id, status: "new").call

      expect(checkout.reload.completed_at).to be_nil
    end
  end
end
