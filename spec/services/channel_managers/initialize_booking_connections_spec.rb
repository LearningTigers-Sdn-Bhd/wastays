# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::InitializeBookingConnections do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel:) }

  describe ".call!" do
    it "reuses the existing primary booking guest" do
      primary_guest = create(:guest, email: "primary@example.com", government_id: nil)
      primary_booking_guest = create(:booking_guest, booking:, guest: primary_guest, is_primary: true)
      create(:guest, email: "incoming@example.com", government_id: nil)

      expect {
        @result = described_class.call!(
          booking:,
          guest_details: { name: "Incoming Guest", email: "incoming@example.com" }
        )
      }.not_to change { [ Guest.count, BookingGuest.count ] }

      expect(@result[:booking_guest]).to eq(primary_booking_guest)
      expect(@result[:folio].booking_billing_party.booking_guest).to eq(primary_booking_guest)
    end

    it "finds an existing guest by normalized government ID before email" do
      government_id_guest = create(:guest, government_id: "passport-123", email: "id@example.com")
      email_guest = create(:guest, government_id: nil, email: "email@example.com")

      expect {
        @result = described_class.call!(
          booking:,
          guest_details: {
            name: "Returning Guest",
            government_id: "  PASSPORT-123  ",
            email: email_guest.email
          }
        )
      }.not_to change(Guest, :count)

      expect(@result[:booking_guest]).to have_attributes(guest: government_id_guest, role: "primary", is_primary: true)
    end

    it "falls back to normalized email and then phone when looking up a guest" do
      email_guest = create(:guest, government_id: nil, email: "returning@example.com", phone: "+60111111111")
      phone_guest = create(:guest, government_id: nil, email: "phone@example.com", phone: "+60222222222")

      email_result = described_class.call!(
        booking:,
        guest_details: { name: "Email Guest", email: "  RETURNING@EXAMPLE.COM  " }
      )
      phone_booking = create(:booking, hotel:)
      phone_result = described_class.call!(
        booking: phone_booking,
        guest_details: { name: "Phone Guest", phone: "  +60222222222  " }
      )

      expect(email_result[:booking_guest].guest).to eq(email_guest)
      expect(phone_result[:booking_guest].guest).to eq(phone_guest)
    end

    it "creates an incomplete channel guest and initializes guest billing" do
      result = described_class.call!(
        booking:,
        guest_details: {
          name: "New Channel Guest",
          email: " NEW.GUEST@EXAMPLE.COM ",
          phone: "+60333333333",
          government_id: " NEW-PASSPORT ",
          country: nil,
          gender: "FEMALE",
          document_type: "PASSPORT"
        }
      )

      booking_guest = result.fetch(:booking_guest)
      guest = booking_guest.guest
      billing_party = result.fetch(:billing_party)
      folio = result.fetch(:folio)

      expect(booking_guest).to have_attributes(booking:, role: "primary", is_primary: true)
      expect(guest).to have_attributes(
        name: "New Channel Guest",
        email: "new.guest@example.com",
        phone: "+60333333333",
        government_id: "new-passport",
        country: hotel.country,
        gender: "female",
        document_type: "passport",
        date_of_birth: nil,
        created_by_hotel: hotel
      )
      expect(guest.metadata).to include(
        "profile_source" => "channel_manager",
        "profile_incomplete" => true
      )
      expect(billing_party).to have_attributes(
        booking:,
        booking_guest:,
        party_kind: "guest",
        archived_at: nil
      )
      expect(billing_party.billing_terms).to be_present
      expect(folio).to have_attributes(
        booking:,
        is_primary: true,
        payer_type: "guest",
        booking_billing_party: billing_party
      )
    end
  end
end
