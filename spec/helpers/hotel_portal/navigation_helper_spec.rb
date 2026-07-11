# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::NavigationHelper, type: :helper do
  let(:hotel) { instance_double(Hotel, name: "Descendant Inn") }
  let(:user) { instance_double(User, superadmin?: false) }

  it "builds breadcrumbs for a two-level active navigation group" do
    leaf = described_class::NavItem.new(label: "Summary", path: "/reports", active: true)
    task_group = described_class::NavItem.new(label: "Reports", path: "/reports", active: false, children: [ leaf ])
    section = described_class::NavSection.new(label: "Navigation", items: [ task_group ])

    allow(helper).to receive(:hotel_sidebar_sections).and_return([ section ])

    expect(helper.hotel_breadcrumb_parts).to eq([
      { type: :section, label: "Reports" },
      { type: :menu, label: "Summary", path: "/reports", siblings: [ { label: "Summary", path: "/reports" } ] }
    ])
  end
end
