# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI Navbar and ProfileMenu", type: :system do
  before { visit "/system-design" }

  def focused_text
    page.evaluate_script("document.activeElement.textContent.trim()")
  end

  def send_key(key)
    page.execute_script(<<~JS)
      document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { key: #{key.to_json}, bubbles: true }))
    JS
  end

  it "opens the profile menu and delegates keyboard behavior to DropdownMenu" do
    find("#preview-profile-trigger").click

    expect(page).to have_css("#preview-profile-menu:popover-open")
    expect(focused_text).to eq("My account")

    send_key("ArrowDown")
    expect(focused_text).to eq("Settings")

    send_key("Escape")
    expect(page).to have_no_css("#preview-profile-menu:popover-open")
    expect(page.evaluate_script("document.activeElement.id")).to eq("preview-profile-trigger")
  end

  it "renders the reduced Navbar without Sidebar triggers" do
    reduced = all("header.panel-navbar[data-sticky='false']", text: "WAStays").last

    expect(reduced).to have_no_css("[command='show-modal']")
    expect(reduced).to have_no_css("[data-controller='panels-ui--sidebar-toggle']")
  end
end
