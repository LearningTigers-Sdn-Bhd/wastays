require "rails_helper"

RSpec.describe Admin::Hotels::SuspendService, type: :service do
  let(:account) { create(:account, status: "active") }
  let(:hotel) { create(:hotel, account: account, status: "live") }

  subject { described_class.new(hotel: hotel) }

  describe "#call" do
    it "suspends the hotel and the account" do
      result = subject.call
      expect(result.success?).to be true
      expect(hotel.reload.status).to eq("suspended")
      expect(account.reload.status).to eq("suspended")
    end
  end
end
