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

    it "rejects an invalid assignee without unassigning the room" do
      create(:booking_room, booking: booking, room_number: "101")
      checkout_request.update!(
        status: "assigned",
        metadata: { "room_number" => "101", "assigned_to" => current_user.id, "assigned_to_name" => current_user.name }
      )

      service = described_class.new(
        hotel: hotel,
        checkout_request: checkout_request,
        assigned_to_id: -1,
        current_user: current_user
      )

      expect { service.call }.to raise_error(ActiveRecord::RecordNotFound, "Housekeeper not found")
      expect(checkout_request.reload.metadata).to include("assigned_to" => current_user.id)
    end
  end
end
