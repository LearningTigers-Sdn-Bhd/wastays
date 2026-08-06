require "rails_helper"

RSpec.describe HotelPortal::Requests::RoomStatusSync do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_numbers: [ "101", "102" ]) }
  let(:booking) { create(:booking, hotel: hotel) }

  def sync(request, kind:, status:)
    described_class.call(request: request, kind: kind, status: status)
  end

  def room_status_for(room_number)
    RoomStatus.find_by(hotel: hotel, room_type: room_type, room_number: room_number)
  end

  describe "housekeeping" do
    let(:request) do
      create(:housekeeping_request, booking: booking, hotel: hotel, room_type: room_type,
             room_number: "101", request_details: "Fresh towels", status: "new")
    end

    it "makes the room dirty when the work is dispatched" do
      sync(request, kind: "housekeeping", status: "new")

      expect(room_status_for("101").status).to eq("cleaning")
    end

    it "makes the room dirty when the work is started" do
      sync(request, kind: "housekeeping", status: "in_progress")

      expect(room_status_for("101").status).to eq("cleaning")
    end

    it "makes the room ready when the work is finished" do
      request.update!(status: "completed")

      sync(request, kind: "housekeeping", status: "completed")

      expect(room_status_for("101").status).to eq("ready")
    end

    # Finishing one job does not make a room ready while another is still owed.
    it "leaves the room alone while other work on it is outstanding" do
      sync(request, kind: "housekeeping", status: "in_progress")
      create(:housekeeping_request, booking: booking, hotel: hotel, room_type: room_type,
             room_number: "101", status: "in_progress")
      request.update!(status: "completed")

      sync(request, kind: "housekeeping", status: "completed")

      expect(room_status_for("101").status).to eq("cleaning")
    end

    it "does nothing for a status that says nothing about the room" do
      sync(request, kind: "housekeeping", status: "failed")

      expect(room_status_for("101")).to be_nil
    end
  end

  describe "checkout" do
    let(:request) do
      create(:check_out_request, booking: booking, status: "in_progress",
             guest_notes: "Leaving early", metadata: { "room_number" => "101" })
    end

    before { create(:booking_room, booking: booking, room_type: room_type, room_number: "101") }

    it "makes the room dirty when the cleaning starts" do
      sync(request, kind: "checkout", status: "in_progress")

      expect(room_status_for("101").status).to eq("cleaning")
    end

    it "makes the room ready when the cleaning finishes" do
      sync(request, kind: "checkout", status: "in_progress")
      request.update!(status: "completed")

      sync(request, kind: "checkout", status: "completed")

      expect(room_status_for("101").status).to eq("ready")
    end

    it "leaves the room alone while housekeeping still owes it work" do
      sync(request, kind: "checkout", status: "in_progress")
      create(:housekeeping_request, booking: booking, hotel: hotel, room_type: room_type,
             room_number: "101", status: "in_progress")
      request.update!(status: "completed")

      sync(request, kind: "checkout", status: "completed")

      expect(room_status_for("101").status).to eq("cleaning")
    end

    it "leaves the room alone while another checkout still owes it work" do
      sync(request, kind: "checkout", status: "in_progress")
      create(:check_out_request, booking: booking, status: "in_progress", metadata: { "room_number" => "101" })
      request.update!(status: "completed")

      sync(request, kind: "checkout", status: "completed")

      expect(room_status_for("101").status).to eq("cleaning")
    end
  end

  # A complaint is about a stay, not a room.
  it "does nothing for a complaint" do
    request = create(:complaint_request, booking: booking, status: "resolved")

    expect { sync(request, kind: "complaint", status: "resolved") }.not_to change(RoomStatus, :count)
  end
end
