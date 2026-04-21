require "rails_helper"

RSpec.describe HotelPortal::Requests::CancelUpdater do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }

  it "cancels and archives a housekeeping request with note" do
    request = create(:housekeeping_request, booking: booking, status: "pending", archived_at: nil)

    result = described_class.new(hotel: hotel, kind: :housekeeping, request_id: request.id, note: "Guest no longer needs this").call

    expect(result).to eq(request)
    expect(request.reload.status).to eq("cancelled")
    expect(request.archived_at).to be_present
    expect(request.internal_notes_list.last["body"]).to include("Guest no longer needs")
  end

  it "returns false when note is blank" do
    request = create(:complaint_request, booking: booking)
    result = described_class.new(hotel: hotel, kind: :complaint, request_id: request.id, note: "").call
    expect(result).to eq(false)
  end
end
