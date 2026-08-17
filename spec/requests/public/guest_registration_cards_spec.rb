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
      get guest_registration_card_path(card.public_token)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(booking.guest_registration_card_number_display)
      expect(response.body).to include("Sign registration card")
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
