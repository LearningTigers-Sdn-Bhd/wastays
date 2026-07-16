# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Concierge QR dialog", type: :system, js: true do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, account: account, plan: plan, status: "registered") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }
  let(:feature_group) { create(:feature_group) }
  let(:concierge_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }

  before do
    driven_by(:cuprite)

    manage_account = Permission.find_or_create_by!(slug: "manage_account") { |permission| permission.name = "Manage Account" }
    manage_profile = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |permission| permission.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: manage_account)
    RolePermission.find_or_create_by!(role: role, permission: manage_profile)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    create(:plan_feature, plan: plan, feature: concierge_feature, enabled: true)

    sign_in_through_ui(user)
    visit hotel_general_settings_path(hotel)
  end

  it "loads the QR actions without leaving General settings" do
    expect(page).to have_no_css("dialog#concierge-qr-code-dialog")
    open_qr_dialog
    expect(page).to have_current_path(hotel_general_settings_path(hotel))
    expect(page).to have_css("#concierge-qr-print-area svg")
    expect(page).to have_link("Download SVG", href: hotel_concierge_qr_path(hotel, format: :svg))
    expect(page).to have_link("Download PNG", href: hotel_concierge_qr_path(hotel, format: :png))
    expect(page).to have_button("Print")
    expect(page).to have_button("Copy URL")
    expect(page.evaluate_script("document.activeElement.id")).to eq("concierge-qr-code-dialog-title")

    page.execute_script("window.print = () => { window.__conciergePrintCalled = true }")
    click_button "Print"
    expect(page.evaluate_script("window.__conciergePrintCalled")).to be(true)

    page.execute_script(<<~JS)
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: { writeText: (value) => { window.__conciergeCopiedUrl = value; return Promise.resolve() } }
      })
    JS
    click_button "Copy URL"
    expect(page).to have_button("Copied")
    expect(page.evaluate_script("window.__conciergeCopiedUrl")).to include("/concierge/#{hotel.slug}")
  end

  it "restores page state after close and supports reopening and Escape" do
    original_overflow = page.evaluate_script("document.body.style.overflow")
    open_qr_dialog

    find("dialog#concierge-qr-code-dialog button[aria-label='Close']").click

    expect(page).to have_no_css("dialog#concierge-qr-code-dialog[open]")
    expect(page).to have_current_path(hotel_general_settings_path(hotel))
    wait_for_body_overflow(original_overflow)
    expect(page.evaluate_script("document.activeElement.textContent.trim()")).to eq("View QR")

    open_qr_dialog

    find("dialog#concierge-qr-code-dialog").send_keys(:escape)
    expect(page).to have_no_css("dialog#concierge-qr-code-dialog[open]")
    expect(page).to have_current_path(hotel_general_settings_path(hotel))
    wait_for_body_overflow(original_overflow)
  end

  def open_qr_dialog
    click_link "View QR"
    expect(page).to have_css("dialog#concierge-qr-code-dialog[open]")
    wait_for_body_overflow("hidden")
  end
end
