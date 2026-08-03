# frozen_string_literal: true

require "rails_helper"

RSpec.describe CheckoutRequests::CompleteRequest do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "completed") }
  let(:checkout_request) { create(:check_out_request, booking: booking) }

  def complete = described_class.new(hotel: hotel, checkout_request: checkout_request).call

  describe "#call" do
    it "completes the request the guest sent" do
      expect(complete).to be_truthy
      expect(checkout_request.reload.status).to eq("completed")
    end

    it "refuses a request that is already finished" do
      checkout_request.update!(status: "completed")

      expect(complete).to be(false)
    end

    context "when the guest is still in the room" do
      let(:booking) { create(:booking, hotel: hotel, status: "checked_in") }

      # Completing the message means doing what it asked for.
      it "checks the booking out" do
        transition = instance_double(Bookings::TransitionStatus, call: double(success?: true))
        allow(Bookings::TransitionStatus)
          .to receive(:new).with(booking: booking, status: "completed").and_return(transition)

        complete

        expect(transition).to have_received(:call)
        expect(checkout_request.reload.status).to eq("completed")
      end

      # An unsettled folio stops the checkout, and so it stops this -- the
      # message cannot be done with while the thing it asked for cannot happen.
      it "refuses when the guest cannot be checked out yet" do
        expect(complete).to be(false)
        expect(checkout_request.reload.status).to eq("pending")
      end
    end
  end
end
