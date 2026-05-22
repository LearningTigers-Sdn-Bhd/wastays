# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentTransaction, type: :model do
  describe "associations" do
    it { should belong_to(:booking_quote).optional }
    it { should belong_to(:booking).optional }
  end

  describe "validations" do
    it { should validate_presence_of(:gateway) }
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(PaymentTransaction::STATUSES) }
  end

  describe "scopes" do
    let!(:captured) { create(:payment_transaction, status: "captured") }
    let!(:failed) { create(:payment_transaction, status: "failed") }
    let!(:pending) { create(:payment_transaction, status: "pending") }

    it ".captured returns captured transactions" do
      expect(described_class.captured).to include(captured)
      expect(described_class.captured).not_to include(failed, pending)
    end

    it ".failed returns failed transactions" do
      expect(described_class.failed).to include(failed)
      expect(described_class.failed).not_to include(captured, pending)
    end
  end
end
