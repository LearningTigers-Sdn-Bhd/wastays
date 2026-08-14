require "rails_helper"

RSpec.describe HotelsSummaryQuery do
  describe "#call" do
    it "counts hotel statuses in SQL-friendly groups" do
      create(:hotel, status: "pending_review")
      create(:hotel, status: "ready_to_launch")
      create(:hotel, status: "live")
      create(:hotel, status: "live")
      create(:hotel, status: "suspended")
      create(:hotel, status: "setup")

      expect(described_class.new.call).to eq(
        total: 6,
        setup: 1,
        pending_review: 1,
        ready_to_launch: 1,
        active: 2,
        suspended: 1
      )
    end
  end
end
