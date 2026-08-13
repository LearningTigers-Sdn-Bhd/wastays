# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Setup::Shell, type: :component do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "setup") }

  let(:presenter) do
    Onboarding::InitializeProgress.new(hotel: hotel).call
    navigation = Onboarding::NavigationState.new(hotel: hotel).call
    HotelPortal::OnboardingPresenter.new(
      hotel: hotel,
      navigation: navigation,
      current_entry: navigation.fetch("property_profile")
    )
  end

  def render_shell(footer: true)
    render_inline(described_class.new(presenter: presenter)) do |shell|
      shell.with_body { "Section body" }
      shell.with_footer { "Section actions" } if footer
    end
  end

  it "scrolls the body while the header and footer keep their place" do
    render_shell

    body = page.find("div.overflow-y-auto", text: "Section body")

    expect(body[:class]).to include("min-h-0", "flex-1")
    expect(page).to have_css("header .tabs-list--line")
    expect(page).to have_css("footer.shrink-0", text: "Section actions")
  end

  it "rests the footer outside the scrolling body instead of overlaying it" do
    render_shell

    expect(page).to have_no_css("footer.sticky, footer.fixed, footer[class*='backdrop-blur']")
    expect(page).to have_no_css("div.overflow-y-auto footer")
  end

  it "carries the page's only rule on the header" do
    render_shell

    # The line-tab underline plus the footer edge are the whole divider budget;
    # sections inside the body separate with spacing alone.
    expect(page).to have_css(".tabs-list--line")
    expect(page).to have_no_css("div.overflow-y-auto [class*='border-t'], div.overflow-y-auto [class*='border-b']")
  end

  it "omits the footer region when a section supplies no actions" do
    render_shell(footer: false)

    expect(page).to have_no_css("footer")
  end
end
