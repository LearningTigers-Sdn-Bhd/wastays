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
  end
end
