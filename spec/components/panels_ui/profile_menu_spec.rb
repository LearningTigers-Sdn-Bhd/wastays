# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::ProfileMenu, type: :component do
  def render_profile_menu
    render_inline(described_class.new(
      id: "hotel-profile",
      display_name: "Aisha Rahman",
      secondary_text: "aisha@example.com",
      trigger_label: "Open account menu"
    )) do |menu|
      menu.with_item(label: "My account", href: "/profile", icon: "user")
      menu.with_item(label: "Settings", href: "/settings", icon: "settings")
      menu.with_sign_out(label: "Sign out", path: "/logout")
    end
  end

  it "composes an accessible DropdownMenu with an account summary" do
    render_profile_menu

    expect(page).to have_css("#hotel-profile[data-controller='panels-ui--dropdown-menu']")
    expect(page).to have_css(
      "button#hotel-profile-trigger[aria-label='Open account menu'][aria-haspopup='menu'][aria-expanded='false'][aria-controls='hotel-profile-menu']"
    )
    expect(page).to have_css("#hotel-profile-menu .dropdown-menu__header[role='presentation']", text: "Aisha Rahman")
    expect(page).to have_css("#hotel-profile-menu .panel-profile-menu__secondary", text: "aisha@example.com")
  end

  it "renders supplied links and a method-aware sign-out action" do
    render_profile_menu

    expect(page).to have_css("a[href='/profile'][role='menuitem']", text: "My account", visible: :all)
    expect(page).to have_css("a[href='/settings'][role='menuitem']", text: "Settings", visible: :all)
    expect(page).to have_css("#hotel-profile-menu [role='separator']", visible: :all)
    expect(page).to have_css("form.contents[action='/logout'] button[role='menuitem']", text: "Sign out", visible: :all)
    expect(page).to have_css("form.contents input[name='_method'][value='delete']", visible: :all)
  end

  it "supports a portal-specific trigger icon and custom menu width" do
    render_inline(described_class.new(
      id: "corporate-profile",
      display_name: "Acme Travel",
      secondary_text: "finance@example.com",
      trigger_label: "Open corporate account menu",
      trigger_icon: "building-2",
      menu_class: "w-80"
    ))

    expect(page).to have_css("#corporate-profile-menu.panel-profile-menu__menu.w-80", visible: :all)
    expect(page).to have_css("#corporate-profile-trigger .panel-profile-menu__avatar-icon", visible: :all)
  end
end
