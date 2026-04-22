require "rails_helper"

RSpec.describe HotelPortal::Requests::ArchiveUpdater do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }

  it "archives a housekeeping request" do
    request = create(:housekeeping_request, booking: booking, archived_at: nil)
    result = described_class.new(hotel: hotel, kind: :housekeeping, request_id: request.id).archive

    expect(result).to eq(request)
    expect(request.reload.archived_at).to be_present
  end

  it "unarchives and resets cancelled request" do
    request = create(:complaint_request, booking: booking, status: "cancelled", archived_at: Time.current)
    result = described_class.new(hotel: hotel, kind: :complaint, request_id: request.id).unarchive

    expect(result).to eq(request)
    expect(request.reload.archived_at).to be_nil
    expect(request.status).to eq("pending")
  end
end
