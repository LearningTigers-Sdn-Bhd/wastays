# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Navbar, type: :component do
  def render_navbar(navigation: true, sticky: true)
    render_inline(described_class.new(key: "hotel", navigation:, sticky:)) do |navbar|
      navbar.with_brand { '<a href="/">WAStays</a>'.html_safe }
      navbar.with_actions { '<a href="/help">Help</a>'.html_safe }
      navbar.with_profile { '<span data-profile>Profile</span>'.html_safe }
    end
  end

  it "renders its slots and both Sidebar controls" do
    render_navbar

    expect(page).to have_css("header.panel-navbar[data-sticky='true']")
    expect(page).to have_link("WAStays", href: "/")
    expect(page).to have_link("Help", href: "/help")
    expect(page).to have_css("[data-profile]", text: "Profile")
    expect(page).to have_css("button[aria-label='Open navigation'][command='show-modal'][commandfor='hotel-sidebar-mobile']")
    expect(page).to have_css("button[data-controller='panels-ui--sidebar-toggle'][data-panels-ui--sidebar-toggle-key-value='hotel']")
  end

  it "omits navigation controls when navigation is disabled" do
    render_navbar(navigation: false, sticky: false)

    expect(page).to have_css("header.panel-navbar[data-sticky='false']")
    expect(page).to have_no_css("button[aria-label='Open navigation']")
    expect(page).to have_no_css("[data-controller='panels-ui--sidebar-toggle']")
  end

  it "requires a key and brand" do
    expect do
      render_inline(described_class.new(key: "")) { |navbar| navbar.with_brand { "Brand" } }
    end.to raise_error(ArgumentError, "Navbar key is required")

    expect do
      render_inline(described_class.new(key: "hotel"))
    end.to raise_error(ArgumentError, "Navbar brand slot is required")
  end
end
