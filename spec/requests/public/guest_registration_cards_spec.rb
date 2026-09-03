# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public::GuestRegistrationCards", type: :request do
  let(:hotel) { create(:hotel, status: "live", guest_registration_card_terms: "Valid photo ID is required at check-in.") }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "Aisha Tan") }
  let!(:card) { booking.create_guest_registration_card!(hotel: hotel) }

  def signature_params(signer_name: "Aisha Tan")
    {
      guest_registration_card: {
        signer_name: signer_name,
        signature_data_url: "data:image/png;base64,abc123"
      }
    }
  end

  describe "GET /guest-registration-card/:token" do
    it "renders the card for signing" do
      booking.update!(guest_home_address: "12 Public Street, Kuching")

      get guest_registration_card_path(card.public_token)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(booking.guest_registration_card_number_display)
      expect(response.body).to include("Address", "12 Public Street, Kuching")
      expect(response.body).to include("Sign registration card")
    end

    it "hides the address when the hotel disables it" do
      hotel.update!(guest_registration_card_fields: %w[phone email])
      booking.update!(guest_home_address: "12 Hidden Street, Kuching")

      get guest_registration_card_path(card.public_token)

      document = Nokogiri::HTML(response.body)
      expect(document.css("dt").map { |node| node.text.strip }).not_to include("Address")
      expect(response.body).not_to include("12 Hidden Street, Kuching")
    end

    it "shows the address for the guest assigned to the public card" do
      additional = create(
        :booking_guest,
        booking: booking,
        is_primary: false,
        home_address_snapshot: "56 Additional Lane, Sibu"
      )
      additional_card = create(:guest_registration_card, hotel: hotel, booking: booking, booking_guest: additional)
      booking.update!(guest_home_address: "12 Primary Street, Kuching")

      get guest_registration_card_path(additional_card.public_token)

      expect(response.body).to include("Address", "56 Additional Lane, Sibu")
      expect(response.body).not_to include("12 Primary Street, Kuching")
    end

    it "404s for an unknown token" do
      get guest_registration_card_path("does-not-exist")

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /guest-registration-card/:token" do
    it "signs the card" do
      patch guest_registration_card_path(card.public_token), params: signature_params

      expect(response).to redirect_to(guest_registration_card_path(card.public_token))
      expect(card.reload.status).to eq("signed")
      expect(card.signer_name).to eq("Aisha Tan")
    end

    it "refuses to sign twice" do
      patch guest_registration_card_path(card.public_token), params: signature_params
      patch guest_registration_card_path(card.public_token), params: signature_params(signer_name: "Someone Else")

      follow_redirect!
      expect(response.body).to include("Delete the existing signature")
      expect(card.reload.signer_name).to eq("Aisha Tan")
    end
  end

  describe "GET /guest-registration-card/:token/pdf" do
    it "refuses before the card is signed" do
      get pdf_guest_registration_card_path(card.public_token)

      expect(response).to redirect_to(guest_registration_card_path(card.public_token))
      follow_redirect!
      expect(response.body).to include("Sign the card first")
    end

    it "serves the PDF once signed" do
      patch guest_registration_card_path(card.public_token), params: signature_params

      get pdf_guest_registration_card_path(card.public_token)

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to start_with("%PDF")
    end
  end

  context "when the hotel has not set its Terms & Conditions" do
    let(:hotel) { create(:hotel, status: "live", guest_registration_card_terms: nil) }

    it "shows the card without offering a way to sign it" do
      get guest_registration_card_path(card.public_token)

      expect(response.body).not_to include("Sign registration card")
      expect(response.body).to include("isn't ready for signature")
    end

    it "refuses to sign" do
      patch guest_registration_card_path(card.public_token), params: signature_params

      expect(response).to redirect_to(guest_registration_card_path(card.public_token))
      follow_redirect!
      expect(response.body).to include("set its Terms")
      expect(card.reload).not_to be_signed
    end
  end
end
