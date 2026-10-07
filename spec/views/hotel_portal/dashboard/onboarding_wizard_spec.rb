# frozen_string_literal: true

require "rails_helper"

RSpec.describe "hotel_portal/dashboard/_onboarding_wizard", type: :view do
  it "shows the property profile as ready without photos" do
    hotel = create(:hotel, address: "12 Beach Road")
    assign(:current_hotel, hotel)

    render partial: "hotel_portal/dashboard/onboarding_wizard"

    document = Nokogiri::HTML.fragment(rendered)
    title = document.css("p").find { |element| element.text == "Property Profile" }
    expect(title["class"]).to include("text-emerald-900")
    expect(rendered).to include("Address and contact details. Photos are optional.")
    expect(hotel.photos).not_to be_attached
  end
end
