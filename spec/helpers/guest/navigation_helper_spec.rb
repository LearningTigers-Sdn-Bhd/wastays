require "rails_helper"

RSpec.describe Guest::NavigationHelper, type: :helper do
  before do
    allow(helper).to receive(:controller_name).and_return(controller_name)
    helper.define_singleton_method(:breadcrumb_appends) { [] }
  end

  let(:controller_name) { "dashboard" }

  it "defines the guest navigation and marks the current destination active" do
    section = helper.guest_sidebar_sections.first

    expect(section.label).to eq("My Account")
    expect(section.items.map(&:label)).to eq([ "Dashboard", "My Bookings", "Refunds" ])
    expect(section.items.select(&:active).map(&:label)).to eq([ "Dashboard" ])
  end

  it "builds breadcrumbs from the active sidebar destination" do
    allow(helper).to receive(:controller_name).and_return("bookings")

    expect(helper.guest_breadcrumb_parts).to eq(
      [
        { type: :section, label: "My Account" },
        {
          type: :menu,
          label: "My Bookings",
          path: helper.guest_bookings_path,
          siblings: [
            { label: "Dashboard", path: helper.guest_dashboard_path },
            { label: "My Bookings", path: helper.guest_bookings_path },
            { label: "Refunds", path: helper.guest_refund_requests_path }
          ]
        }
      ]
    )
  end

  it "appends controller-provided detail breadcrumbs" do
    allow(helper).to receive(:controller_name).and_return("refund_requests")
    helper.define_singleton_method(:breadcrumb_appends) do
      [
        { label: "WS-123", path: "/guest/bookings/123" },
        { label: "Refund Details", path: nil, siblings: nil }
      ]
    end

    expect(helper.guest_breadcrumb_parts.last(2)).to eq(
      [
        { label: "WS-123", path: "/guest/bookings/123" },
        { label: "Refund Details", path: nil, siblings: nil }
      ]
    )
  end
end
