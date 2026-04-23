require "rails_helper"

RSpec.describe Admin::Salespersons::Filter, type: :service do
  let(:account) { create(:account) }
  let!(:salesperson) { create(:user, :salesperson, account: account, name: "Mira Tan", email: "mira@example.com") }
  let!(:hotel) { create(:hotel, account: account, name: "Luma Stay", salesperson: salesperson) }

  describe "#call" do
    it "filters by name" do
      filter = described_class.new(account.users, "Mira")
      expect(filter.call).to include(salesperson)
    end

    it "filters by hotel name" do
      filter = described_class.new(account.users, "Luma")
      expect(filter.call).to include(salesperson)
    end

    it "excludes non-matching" do
      filter = described_class.new(account.users, "NoMatch")
      expect(filter.call).to be_empty
    end
  end

  describe ".matches?" do
    it "matches by email" do
      expect(described_class.matches?(salesperson, "mira@example.com")).to be true
    end
  end
end
