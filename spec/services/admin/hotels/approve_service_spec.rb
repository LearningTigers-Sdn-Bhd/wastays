require "rails_helper"

RSpec.describe Admin::Hotels::ApproveService, type: :service do
  let(:account) { create(:account, status: "pending") }
  let(:hotel) { create(:hotel, account: account, status: "pending_review") }

  subject { described_class.new(hotel: hotel) }

  describe "#call" do
    it "approves the hotel and activates the account" do
      result = subject.call
      expect(result.success?).to be true
      expect(hotel.reload.status).to eq("approved")
      expect(account.reload.status).to eq("active")
    end

    context "when reactivating a suspended hotel" do
      let(:account) { create(:account, status: "suspended") }
      let(:hotel) { create(:hotel, account: account, status: "suspended") }

      it "identifies the reactivation" do
        result = subject.call
        expect(result.success?).to be true
        expect(result.reactivating?).to be true
      end
    end
  end
end
