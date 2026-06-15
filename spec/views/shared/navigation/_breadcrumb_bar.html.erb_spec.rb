require "rails_helper"

RSpec.describe "shared/navigation/_breadcrumb_bar.html.erb", type: :view do
  it "renders dropdown, current, and tab-controlled breadcrumb items" do
    render partial: "shared/navigation/breadcrumb_bar", locals: {
      parts: [
        {
          type: :menu,
          label: "Bookings",
          path: "/bookings",
          siblings: [ { label: "Arrivals", path: "/arrivals" } ]
        },
        { label: "ABC123" },
        { label: "Booking Details", tab_label: true }
      ]
    }

    expect(rendered).to include("Open Bookings navigation")
    expect(rendered).to include(%(href="/arrivals"))
    expect(rendered).to include("ABC123")
    expect(rendered).to include("data-tabs-breadcrumb-label>Booking Details</span>")
  end
end
