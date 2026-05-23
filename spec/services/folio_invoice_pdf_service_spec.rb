# frozen_string_literal: true

require "rails_helper"

RSpec.describe FolioInvoicePdfService do
  let(:booking_folio) { create(:booking_folio) }
  let(:booking) { booking_folio.booking }
  let(:service) { described_class.new(booking) }

  describe "#generate" do
    it "returns PDF data" do
      # Basic check to ensure it doesn't crash
      expect(service.generate).to be_a(String)
    end
  end
end
