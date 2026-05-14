# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingFolio, type: :model do
  describe "associations" do
    it { should belong_to(:booking) }
  end

  describe "validations" do
    let(:booking) { create(:booking) }
    subject { BookingFolio.new(booking: booking, folio_number: 123, status: "open") }

    it { should validate_presence_of(:folio_number) }
    it { should validate_uniqueness_of(:folio_number) }
    it { should validate_presence_of(:status) }
  end

  describe "#outstanding_balance" do
    it "returns 0.0" do
      folio = BookingFolio.new
      expect(folio.outstanding_balance).to eq(0.0)
    end
  end
end
