require 'rails_helper'

RSpec.describe "static_pages/home.html.tailwindcss", type: :view do
  it "renders booking experience with step-attached connectors and no chevron" do
    render template: "static_pages/home"

    expect(rendered).to include("Instant room booking")
    expect(rendered.scan("booking-step-connector").size).to eq(4)
    expect(rendered).not_to include('d="M9 5l7 7-7 7"')
    expect(rendered).not_to include("absolute inset-x-0 top-10 grid-cols-5")
    expect(rendered).not_to include("booking-step-icon-track")
  end

  it "renders the dashboard mockup with mobile-safe responsive layout classes" do
    render template: "static_pages/home"

    expect(rendered).to include("Recent Conversations")
    expect(rendered).to include("grid-cols-2 lg:grid-cols-4")
    expect(rendered).to include("grid-cols-1 lg:grid-cols-5")
    expect(rendered).to include("col-span-1 lg:col-span-3")
    expect(rendered).to include("col-span-1 lg:col-span-2")
  end
end
