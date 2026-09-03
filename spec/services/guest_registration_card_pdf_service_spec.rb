require "rails_helper"

RSpec.describe GuestRegistrationCardPdfService do
  let(:hotel) { create(:hotel, name: "Seaview Hotel", city: "Kota Kinabalu", country: "Malaysia") }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      guest_name: "Aisha Tan",
      guest_email: "aisha.tan@example.com",
      guest_phone: "+60123456789",
      guest_country: "Malaysia",
      guest_home_address: "12 Booking Road, Kota Kinabalu",
      confirmation_token: "WS-GRC1",
      adults: 1,
      children: 1,
      total_amount: 300.0,
      check_in: Date.new(2026, 7, 11),
      check_out: Date.new(2026, 7, 13))
  end
  let(:card) { create(:guest_registration_card, booking: booking, hotel: hotel) }
  let(:presenter) { HotelPortal::GuestRegistrationCardPresenter.new(card, booking) }

  before do
    create(:booking_guest, booking: booking, guest: create(:guest), is_primary: true,
      name_snapshot: "Aisha Tan", email_snapshot: "aisha.tan@example.com",
      phone_snapshot: "+60123456789", country_snapshot: "Malaysia",
      home_address_snapshot: "34 Snapshot Street, Kota Kinabalu")
    create(:property_policy, hotel: hotel, check_in_time: "15:00", check_out_time: "12:00")
  end

  def pdf_text(pdf)
    PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")
  end

  it "generates a valid PDF binary" do
    pdf = described_class.new(card, booking, presenter).generate

    expect(pdf).to be_a(String)
    expect(pdf.force_encoding("BINARY")[0, 5]).to eq("%PDF-")
    expect(pdf.bytesize).to be > 1000
  end

  it "renders guest details, combined check-in/check-out, and pluralized guest counts" do
    text = pdf_text(described_class.new(card, booking, presenter).generate)

    expect(text).to include("Aisha Tan", "aisha.tan@example.com", "+60123456789", "1 adult, 1 child")
    expect(text).to include("Address", "34 Snapshot Street, Kota Kinabalu")
    expect(text).not_to include("12 Booking Road, Kota Kinabalu")
    expect(text).to include("11 Jul 2026, 03:00 PM")
    expect(text).to include("13 Jul 2026, 12:00 PM")
  end

  it "omits the guest address when the field is disabled" do
    hotel.update!(guest_registration_card_fields: %w[phone email])

    text = pdf_text(described_class.new(card, booking, presenter).generate)

    expect(text).not_to include("34 Snapshot Street, Kota Kinabalu")
  end

  it "renders the hotel's fixed terms and conditions when configured" do
    hotel.update!(guest_registration_card_terms: "Valid photo ID is required at check-in.")

    text = pdf_text(described_class.new(card, booking, presenter).generate)

    expect(text).to include("Terms & Conditions", "Valid photo ID is required at check-in.")
  end

  it "omits the terms and conditions section when the hotel has none configured" do
    text = pdf_text(described_class.new(card, booking, presenter).generate)

    expect(text).not_to include("Terms & Conditions")
  end

  it "does not repeat the missing-terms notice under a configured Terms & Conditions block" do
    hotel.update!(guest_registration_card_terms: "Valid photo ID is required at check-in.")

    text = pdf_text(described_class.new(card, booking, presenter).generate)

    expect(text).not_to include("Hotel terms are not configured.")
  end

  it "still shows the missing-terms notice when nothing is configured at all" do
    hotel.property_policy.update!(cancellation_policy: nil)

    text = pdf_text(described_class.new(card, booking, presenter).generate)

    expect(text).to include("Hotel terms are not configured.")
  end

  it "renders boat transfer details only when the primary guest has boat times" do
    primary_guest = booking.booking_guests.find(&:primary?)
    primary_guest.update!(boat_in_at: Time.zone.local(2026, 7, 11, 16, 30), boat_out_at: Time.zone.local(2026, 7, 13, 13, 0))

    text = pdf_text(described_class.new(card, booking, presenter).generate)

    expect(text).to include("Boat-in", "Boat-out")
  end

  it "omits boat transfer details when the primary guest has no boat times" do
    text = pdf_text(described_class.new(card, booking, presenter).generate)

    expect(text).not_to include("Boat-in")
  end

  it "renders special requests as Remark" do
    booking.update!(special_requests: "Late checkout requested")

    text = pdf_text(described_class.new(card, booking, presenter).generate)

    expect(text).to include("Remark", "Late checkout requested")
  end

  it "does not render internal notes as Please Note" do
    booking.update!(internal_notes: "VIP guest, prioritize service.")

    text = pdf_text(described_class.new(card, booking, presenter).generate)

    expect(text).not_to include("Please Note", "VIP guest, prioritize service.")
  end

  it "renders CJK text without raising an encoding error" do
    booking.update!(special_requests: "入住时间下午2点")

    pdf = described_class.new(card, booking, presenter).generate

    expect(pdf.force_encoding("BINARY")[0, 5]).to eq("%PDF-")
  end

  it "renders signer name and does not blow up on an undecodable signature image" do
    card.update_columns(status: "signed", signer_name: "Jane Guest", signature_data_url: "data:image/png;base64,not-a-real-image", signed_at: Time.current)

    text = pdf_text(described_class.new(card, booking, presenter).generate)

    expect(text).to include("Signed by Jane Guest")
  end

  it "renders a blank signature line when the card is not signed" do
    text = pdf_text(described_class.new(card, booking, presenter).generate)

    expect(text).to include("Signature")
    expect(text).not_to include("Signed by")
  end
end
