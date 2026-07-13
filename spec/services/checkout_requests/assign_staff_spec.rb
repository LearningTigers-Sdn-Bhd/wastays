# frozen_string_literal: true

require "rails_helper"

RSpec.describe CheckoutRequests::AssignStaff do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:checkout_request) { create(:check_out_request, booking: booking) }
  let(:current_user) { create(:user) }

  describe "#call" do
    it "exists and can be instantiated" do
      service = described_class.new(
        hotel: hotel,
        checkout_request: checkout_request,
        assigned_to_id: nil,
        current_user: current_user
      )
      expect(service).to respond_to(:call)
    end
  end
end
