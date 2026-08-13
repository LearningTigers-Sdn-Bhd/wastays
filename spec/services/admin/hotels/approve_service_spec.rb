require "rails_helper"

RSpec.describe Admin::Hotels::ApproveService, type: :service do
  let(:account) { create(:account, status: "pending") }
  let(:hotel) { create(:hotel, account: account, status: "pending_review") }

  subject { described_class.new(hotel: hotel) }

  describe "#call" do
    it "directs pending-review hotels to the canonical onboarding approval" do
      result = subject.call
      expect(result.success?).to be false
      expect(result.error).to include("Only suspended properties")
      expect(hotel.reload.status).to eq("pending_review")
      expect(account.reload.status).to eq("pending")
    end

    context "when reactivating a suspended hotel" do
      let(:account) { create(:account, status: "suspended") }
      let(:hotel) { create(:hotel, account: account, status: "suspended") }

      it "identifies the reactivation" do
        result = subject.call
        expect(result.success?).to be true
        expect(result.reactivating?).to be true
        expect(hotel.reload.status).to eq("live")
        expect(account.reload.status).to eq("active")
      end
    end
  end
end
