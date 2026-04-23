require "rails_helper"

RSpec.describe Admin::Salespersons::UpdateService, type: :service do
  let(:account) { create(:account) }
  let(:salesperson) { create(:user, :salesperson, account: account) }
  let(:hotel) { create(:hotel, account: account, salesperson: salesperson) }
  let(:params) { { name: "Updated Name" } }
  let(:hotel_ids) { [ hotel.id ] }

  subject { described_class.new(salesperson: salesperson, params: params, hotel_ids: hotel_ids) }

  describe "#call" do
    it "updates the salesperson" do
      result = subject.call
      expect(result.success?).to be true
      expect(salesperson.reload.name).to eq("Updated Name")
    end

    context "when no hotels are assigned" do
      let(:hotel_ids) { [] }
      before { salesperson } # Ensure created before count

      it "removes the salesperson" do
        result = nil
        expect {
          result = subject.call
        }.to change(User, :count).by(-1)
        expect(result.action).to eq(:destroyed)
      end
    end
  end
end
