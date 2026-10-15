# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::Pagination, type: :component do
  def pagy_at(page, count: 60)
    pagy, = Object.new.extend(Pagy::Method).send(
      :pagy, :offset, (1..count).to_a, limit: 25,
      request: { base_url: "http://test.host", path: "/guest/bookings", params: { "q" => "Sea", "page" => page.to_s } }
    )
    pagy
  end

  it "shows the page and links both ways from a middle page" do
    render_inline(described_class.new(pagy: pagy_at(2)))

    expect(page).to have_css("nav.guest-pagination [aria-current='page']", text: "Page 2 of 3")
    expect(page).to have_css("a[rel='prev'][href*='page=1'][href*='q=Sea']", text: "Previous")
    expect(page).to have_css("a[rel='next'][href*='page=3']", text: "Next")
  end

  it "disables Previous on the first page" do
    render_inline(described_class.new(pagy: pagy_at(1)))

    expect(page).to have_css("span.guest-pagination__control[aria-disabled='true']", text: "Previous")
    expect(page).to have_no_css("a[rel='prev']")
  end

  it "draws nothing on a single page" do
    render_inline(described_class.new(pagy: pagy_at(1, count: 5)))

    expect(page).to have_no_css("nav")
  end
end
