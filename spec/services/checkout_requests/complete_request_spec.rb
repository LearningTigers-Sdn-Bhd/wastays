# frozen_string_literal: true

require "rails_helper"

RSpec.describe CheckoutRequests::CompleteRequest do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:checkout_request) { create(:check_out_request, booking: booking) }

  describe "#call" do
    it "exists and can be instantiated" do
      service = described_class.new(
        hotel: hotel,
        checkout_request: checkout_request
      )
      expect(service).to respond_to(:call)
    end
  end
end
