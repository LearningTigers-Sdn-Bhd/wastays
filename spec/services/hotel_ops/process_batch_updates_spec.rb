# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelOps::ProcessBatchUpdates do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:rate_plan) { create(:rate_plan, room_type: room_type) }

  let(:updates) do
    [
      {
        start_date: Date.today.to_s,
        end_date: (Date.today + 1).to_s,
        apply_inventory: true,
        apply_rates: true,
        room_type_ids: [ room_type.id ],
        rate_plan_ids: [ rate_plan.id ],
        price: 100,
        quantity: 10,
        modified_fields: [ "price", "quantity" ]
      }
    ]
  end

  subject { described_class.new(hotel: hotel, updates: updates, user: user) }

  describe "#call" do
    it "calls ApplyInventoryDashboardSelection for each update" do
      expect_any_instance_of(HotelOps::ApplyInventoryDashboardSelection).to receive(:call).and_return({ success: true })

      result = subject.call
      expect(result[:success]).to be true
      expect(result[:message]).to eq("All changes synced successfully.")
    end

    it "triggers a SyncJob if hotel has a preferred channel manager" do
      hotel.update!(preferred_channel_manager: "staah")
      expect_any_instance_of(HotelOps::ApplyInventoryDashboardSelection).to receive(:call).and_return({ success: true })
      expect(ChannelManagers::SyncJob).to receive(:perform_later).at_least(:once)

      subject.call
    end

    context "when an update fails" do
      it "returns failure and rolls back" do
        expect_any_instance_of(HotelOps::ApplyInventoryDashboardSelection).to receive(:call).and_return({ success: false, error: "Validation failed" })

        result = subject.call
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Validation failed")
      end
    end

    context "when an unexpected error occurs" do
      it "handles and logs the error" do
        expect_any_instance_of(HotelOps::ApplyInventoryDashboardSelection).to receive(:call).and_raise("Something went wrong")

        result = subject.call
        expect(result[:success]).to be false
        expect(result[:error]).to include("Something went wrong")
      end
    end
  end
end
