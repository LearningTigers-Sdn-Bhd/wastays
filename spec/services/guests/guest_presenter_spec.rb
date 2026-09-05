# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guests::GuestPresenter do
  let(:guest) { build(:guest, name: "John Doe", gender: "male", document_type: "passport", country: "Malaysia") }
  let(:presenter) { described_class.new(guest) }

  describe "#name" do
    it "returns the guest name" do
      expect(presenter.name).to eq("John Doe")
    end
  end

  describe "#formatted_gender" do
    it "returns capitalized gender" do
      expect(presenter.formatted_gender).to eq("Male")
    end

    it "returns nil when the gender is blank" do
      guest.gender = nil
      expect(presenter.formatted_gender).to be_nil
    end
  end

  describe "#formatted_document_type" do
    it "names the document the guest handed over" do
      expect(presenter.formatted_document_type).to eq("Passport")
    end

    it "falls back to a generic document label" do
      guest.document_type = nil
      expect(presenter.formatted_document_type).to eq("Identity document")
    end
  end

  describe "#formatted_country" do
    it "returns the country" do
      expect(presenter.formatted_country).to eq("Malaysia")
    end

    it "returns nil when the country is blank" do
      guest.country = nil
      expect(presenter.formatted_country).to be_nil
    end
  end

  describe "#date_of_birth_formatted" do
    it "returns nil when there is no date of birth" do
      guest.date_of_birth = nil
      expect(presenter.date_of_birth_formatted).to be_nil
    end
  end

  describe "#last_stay_checkout_date" do
    it "returns nil when there is no check-out date" do
      expect(presenter.last_stay_checkout_date(nil)).to be_nil
    end
  end

  describe "#normalized_document_type" do
    it "reads a national identity card as a MyKad for a Malaysian guest" do
      guest.country = "Malaysia"
      guest.document_type = "national_id"

      expect(presenter.normalized_document_type).to eq("malaysian_nric")
    end

    it "reads a MyKad as a national identity card for a foreign guest" do
      guest.country = "Japan"
      guest.document_type = "malaysian_nric"

      expect(presenter.normalized_document_type).to eq("national_id")
    end

    it "leaves every other pairing alone" do
      guest.country = "Japan"
      guest.document_type = "passport"

      expect(presenter.normalized_document_type).to eq("passport")

      guest.document_type = nil

      expect(presenter.normalized_document_type).to be_nil
    end
  end

  describe "#identity_number_label" do
    it "names the document the guest handed over" do
      guest.country = "Japan"

      guest.document_type = "passport"
      expect(presenter.identity_number_label).to eq("Passport number")

      guest.document_type = "national_id"
      expect(presenter.identity_number_label).to eq("National identity card number")

      guest.country = "Malaysia"
      guest.document_type = "national_id"
      expect(presenter.identity_number_label).to eq("MyKad number")
    end

    it "stays generic until a document type is chosen" do
      guest.document_type = nil

      expect(presenter.identity_number_label).to eq("Identity document number")
    end
  end

  describe "safe attributes" do
    it "handles decryption errors gracefully" do
      allow(guest).to receive(:name).and_raise(ActiveRecord::Encryption::Errors::Decryption)
      expect(presenter.name).to eq("Encrypted data")
    end
  end
end
