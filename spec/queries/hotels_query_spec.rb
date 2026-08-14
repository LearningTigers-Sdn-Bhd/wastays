require "rails_helper"

RSpec.describe HotelsQuery do
  describe "#call" do
    it "filters hotels still in setup" do
      setup = create(:hotel, status: "setup")
      create(:hotel, status: "live")
      create(:hotel, status: "pending_review")

      expect(described_class.new.call(status: "setup")).to contain_exactly(setup)
    end

    it "filters live hotels as the active group" do
      live = create(:hotel, status: "live")
      create(:hotel, status: "suspended")
      create(:hotel, status: "setup")

      expect(described_class.new.call(status: "active")).to contain_exactly(live)
    end

    it "filters hotels awaiting review" do
      pending = create(:hotel, status: "pending_review")
      create(:hotel, status: "setup")

      expect(described_class.new.call(status: "pending_review")).to contain_exactly(pending)
    end

    it "filters hotels approved and awaiting their launch decision" do
      ready = create(:hotel, status: "ready_to_launch")
      create(:hotel, status: "pending_review")

      expect(described_class.new.call(status: "ready_to_launch")).to contain_exactly(ready)
    end
  end
end
