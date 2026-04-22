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
end
