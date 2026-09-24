require "rails_helper"

RSpec.describe Guest::NavigationHelper, type: :helper do
  before do
    allow(helper).to receive(:controller_name).and_return(controller_name)
    helper.define_singleton_method(:breadcrumb_appends) { [] }
  end

  let(:controller_name) { "dashboard" }

  it "defines the guest destinations and marks the current one active" do
    items = helper.guest_nav_items

    expect(items.map(&:label)).to eq([ "Home", "Bookings", "Refunds" ])
    expect(items.select(&:active).map(&:label)).to eq([ "Home" ])
  end

  it "titles a top-level page after its destination, with no way back" do
    expect(helper.guest_page_title).to eq("Home")
    expect(helper.guest_back_path).to be_nil
  end

  context "on a page the controller appended to" do
    let(:controller_name) { "refund_requests" }

    before do
      helper.define_singleton_method(:breadcrumb_appends) do
        [
          { label: "WS-123", path: "/guest/bookings/123" },
          { label: "Request Refund", path: nil, siblings: nil }
        ]
      end
    end

    it "titles the page after the last step and goes back to the step before" do
      expect(helper.guest_page_title).to eq("Request Refund")
      expect(helper.guest_back_path).to eq("/guest/bookings/123")
    end
  end
end
