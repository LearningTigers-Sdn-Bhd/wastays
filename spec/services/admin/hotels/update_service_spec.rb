require "rails_helper"

RSpec.describe Admin::Hotels::UpdateService, type: :service do
  let(:account) { create(:account) }
  let(:current_user) { create(:user, :superadmin, account: account) }
  let(:hotel) { create(:hotel, account: account, name: "Old Name") }
  let(:hotel_params) { { name: "New Name" } }
  let(:salesperson_params) { { name: "New Salesperson", email: "sales@example.com" } }

  subject do
    described_class.new(
      hotel: hotel,
      hotel_params: hotel_params,
      salesperson_params: salesperson_params,
      current_user: current_user
    )
  end

  describe "#call" do
    it "updates the hotel and syncs the salesperson" do
      result = subject.call
      expect(result.success?).to be true
      expect(hotel.reload.name).to eq("New Name")
      expect(hotel.salesperson.name).to eq("New Salesperson")
    end

    context "when hotel update fails" do
      let(:hotel_params) { { name: "" } }

      it "returns a failure result" do
        result = subject.call
        expect(result.success?).to be false
        expect(result.error).to include("Name can't be blank")
      end
    end

    context "when sell_mode is updated" do
      let(:hotel_params) { { name: "Updated Hotel", sell_mode: "per_person" } }

      it "rejects the whole update" do
        result = subject.call
        expect(result.success?).to be false
        expect(result.error).to include("Sell mode cannot be changed after the hotel is created")
        expect(hotel.reload).to have_attributes(name: "Old Name", sell_mode: "per_room")
      end
    end
  end
end
