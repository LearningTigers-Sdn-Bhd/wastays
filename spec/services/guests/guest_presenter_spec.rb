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

  describe "#gender" do
    it "returns capitalized gender" do
      expect(presenter.gender).to eq("Male")
    end

    it "returns dash if blank" do
      guest.gender = nil
      expect(presenter.gender).to eq("—")
    end
  end

  describe "#document_type" do
    it "returns uppercased document type" do
      expect(presenter.document_type).to eq("PASSPORT")
    end

    it "returns dash if blank" do
      guest.document_type = nil
      expect(presenter.document_type).to eq("—")
    end
  end

  describe "#country" do
    it "returns the country" do
      expect(presenter.country).to eq("Malaysia")
    end
  end

  describe "safe attributes" do
    it "handles decryption errors gracefully" do
      allow(guest).to receive(:name).and_raise(ActiveRecord::Encryption::Errors::Decryption)
      expect(presenter.name).to eq("Encrypted data")
    end
  end
end
