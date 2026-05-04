require 'rails_helper'

RSpec.describe "static_pages/home.html.tailwindcss", type: :view do
  it "does not render booking experience section" do
    render template: "static_pages/home"

    expect(rendered).not_to include("Instant room booking")
    expect(rendered).not_to include("booking-step-connector")
    expect(rendered).not_to include("booking-step-icon-track")
  end

  it "renders the dashboard mockup with mobile-safe responsive layout classes" do
    render template: "static_pages/home"

    expect(rendered).to include("Recent Requests")
    expect(rendered).to include("grid-cols-2 lg:grid-cols-4")
    expect(rendered).to include("grid-cols-1 lg:grid-cols-5")
    expect(rendered).to include("col-span-1 lg:col-span-3")
    expect(rendered).to include("col-span-1 lg:col-span-2")
  end
end
