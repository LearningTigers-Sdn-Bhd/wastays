require "rails_helper"

RSpec.describe GuestArrival::CreateOrMatchGuest do
  let(:params) do
    {
      name: "Jane Doe",
      email: "JANE@EXAMPLE.COM",
      phone: "+60111111111",
      city: "kota kinabalu",
      government_id: "A123456",
      gender: "FEMALE",
      country: "Singapore",
      document_type: "PASSPORT"
    }
  end

  it "creates new guest when no match exists" do
    result = described_class.new(params).call

    expect(result.success?).to be(true)
    expect(result.guest).to be_persisted
    expect(result.guest.email).to eq("jane@example.com")
    expect(result.guest.city).to eq("Kota Kinabalu")
    expect(result.is_repeat?).to be(false)
  end

  it "matches existing guest by phone" do
    existing = create(:guest, government_id: "A123456", email: "old@example.com", phone: "+60111111111")

    result = described_class.new(params).call

    expect(result.guest.id).to eq(existing.id)
  end

  it "marks repeat guest when guest has revenue-generating bookings" do
    guest = create(:guest, government_id: "A123456", phone: "+60111111111")
    booking = create(:booking, status: "completed")
    create(:booking_guest, booking: booking, guest: guest, is_primary: true)

    result = described_class.new(params).call

    expect(result.is_repeat?).to be(true)
  end

  it "sets created_by_hotel_id for new guests" do
    hotel = create(:hotel)
    params[:created_by_hotel_id] = hotel.id
    result = described_class.new(params).call

    expect(result.guest.created_by_hotel_id).to eq(hotel.id)
  end

  it "stores marketing and privacy consent in metadata" do
    params[:marketing_consent] = "1"
    params[:privacy_consent] = "1"
    result = described_class.new(params).call

    expect(result.guest.metadata["marketing_consent"]).to be(true)
    expect(result.guest.metadata["privacy_consent"]).to be(true)
    expect(result.guest.metadata["marketing_consent_updated_at"]).to be_present
    expect(result.guest.metadata["privacy_consent_updated_at"]).to be_present
  end

  it "fills blank city for an existing guest" do
    existing = create(:guest, email: "jane@example.com", city: nil)

    result = described_class.new(params).call

    expect(result.guest.id).to eq(existing.id)
    expect(existing.reload.city).to eq("Kota Kinabalu")
  end
end
