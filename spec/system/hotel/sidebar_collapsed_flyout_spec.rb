# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel collapsed sidebar flyout", type: :system do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, account: account, plan: plan, status: "live") }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account) }

  before do
    driven_by(:cuprite)

    %w[view_reports view_bookings view_audit_logs manage_hotel_profile].each do |slug|
      permission = Permission.find_by(slug: slug) || create(:permission, name: slug.tr("_", " ").titleize, slug: slug)
      create(:role_permission, role: role, permission: permission)
    end
    create(:user_hotel_access, user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)
    visit hotel_reports_path(hotel)
  end

  it "expands the compact rail on hover and collapses after pointer leave" do
    expect(page).to have_css("#hotel-reports-sidebar[data-collapsed='true']")
    compact_section_spacing = page.evaluate_script(<<~JS)
      (() => {
        const groups = Array.from(document.querySelectorAll("#hotel-reports-sidebar .panel-sidebar__section"))
        const styles = window.getComputedStyle(groups[0])
        return parseFloat(styles.marginTop) + parseFloat(styles.paddingTop)
      })()
    JS
    expect(compact_section_spacing).to be <= 8

    find("#hotel-reports-sidebar").hover

    expect(page).to have_css("#hotel-reports-sidebar[data-collapsed='false'][data-locked='false']")
    within("#hotel-reports-sidebar") do
      expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Compliance", visible: :visible)
      expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Financial", visible: :visible)
      expect(page).to have_no_css(".panel-sidebar__flyout[data-state='open']")
      expect(page).to have_no_css("[role='tooltip'][data-state='open']", visible: :visible)
    end

    find("main").hover

    expect(page).to have_css("#hotel-reports-sidebar[data-collapsed='true'][data-locked='false']")
  end

  xit "pins a clicked group until it is dismissed" do
    find('button[aria-label="Lock navigation open"]').click

    within("#hotel-reports-sidebar") do
      find("summary.sidebar-group-parent", text: "Financial", visible: :all).click

      expect(page).to have_css("details.sidebar-group-active[open][data-sidebar-pinned='true']")
    end

    find("main").hover

    within("#hotel-reports-sidebar") do
      expect(page).to have_css("details.sidebar-group-active[open][data-sidebar-pinned='true']")

      find("summary.sidebar-group-parent", text: "Financial", visible: :all).hover
    end

    find("main").hover

    within("#hotel-reports-sidebar") do
      expect(page).to have_css("details.sidebar-group-active[open][data-sidebar-pinned='true']")
    end

    page.send_keys(:escape)

    within("#hotel-reports-sidebar") do
      expect(page).to have_no_css("details.sidebar-group[open]")
    end

    find('button[aria-label="Unlock navigation"]').click

    within("#hotel-reports-sidebar") do
      expect(page).to have_css("details.sidebar-group-active[open]")
    end
  end

  it "renders report flyout leaves directly in a compact rail, without a wrapping Reports group" do
    within("#hotel-reports-sidebar") do
      open_popover_with_keyboard(find("button.panel-sidebar__group-trigger[aria-label='Financial']", visible: :all))
      expect(page).to have_css(".panel-sidebar__flyout[data-state='open']")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger[aria-label='Reports']", visible: :all)
      expect(page).to have_no_css(".panel-sidebar__flyout [data-sidebar-group-item]", visible: :all)
      expect(page).to have_css(".panel-sidebar__flyout a.panel-sidebar__child", text: "Summary", visible: :visible)
    end
  end

  it "closes compact rail flyouts on Escape" do
    within("#hotel-reports-sidebar") do
      open_popover_with_keyboard(find("button.panel-sidebar__group-trigger[aria-label='Financial']", visible: :all))

      expect(page).to have_css(".panel-sidebar__flyout[data-state='open']")
    end

    page.send_keys(:escape)

    within("#hotel-reports-sidebar") do
      expect(page).to have_no_css(".panel-sidebar__flyout[data-state='open']", visible: :all)
    end
  end

  it "keeps the most-specific parent route active on nested pages" do
    nested_report_path = "#{hotel_reports_path(hotel)}/nested"
    find('button[aria-label="Lock navigation open"]').click

    page.execute_script(<<~JS)
      window.history.pushState({}, "", "#{nested_report_path}")
      document.dispatchEvent(new Event("turbo:load"))
    JS

    within("#hotel-reports-sidebar") do
      expect(page).to have_css("a.panel-sidebar__child[aria-current='page']", text: "Summary")
      expect(page).to have_css("[data-sidebar-group-item][data-sidebar-active] .panel-sidebar__group[data-state='open']")
    end
  end

  # Reports carries four groups now, so the two-groups-open case belongs back
  # here: Financial is active on this page, Logs is the one the reader opens.
  it "keeps active and user-opened groups expanded through Turbo navigation" do
    find('button[aria-label="Lock navigation open"]').click

    within("#hotel-reports-sidebar") do
      expect(page).to have_css("[data-sidebar-group-item][data-sidebar-active] button.panel-sidebar__group-trigger[aria-expanded='true']", text: "Financial")
      find("button.panel-sidebar__group-trigger", text: "Logs", visible: :all).click
      expect(page).to have_css("button.panel-sidebar__group-trigger[aria-expanded='true']", text: "Logs")
    end

    page.execute_script(<<~JS)
      document.addEventListener("turbo:before-visit", () => {
        window.sidebarActiveGroupOpenBeforeVisit =
          document.querySelector("#hotel-reports-sidebar [data-sidebar-group-item][data-sidebar-active] .panel-sidebar__group-trigger")?.getAttribute("aria-expanded") === "true"
      }, { once: true })
    JS

    within("#hotel-reports-sidebar") do
      click_link "Refund Report"
    end

    expect(page).to have_current_path(refund_report_hotel_reports_path(hotel))
    expect(page.evaluate_script("window.sidebarActiveGroupOpenBeforeVisit")).to be(true)
    expect(page).to have_css("#hotel-reports-sidebar[data-collapsed='false'][data-locked='true']")

    within("#hotel-reports-sidebar") do
      expect(page).to have_css("a.panel-sidebar__child[aria-current='page']", text: "Refund Report")
      expect(page).to have_css("[data-sidebar-group-item][data-sidebar-active] button.panel-sidebar__group-trigger[aria-expanded='true']", text: "Financial")
      expect(page).to have_css("button.panel-sidebar__group-trigger[aria-expanded='true']", text: "Logs")
    end
  end

  def open_popover_with_keyboard(trigger)
    page.execute_script(<<~JS)
      const trigger = document.getElementById(#{trigger[:id].to_json})
      trigger.focus()
      trigger.dispatchEvent(
        new KeyboardEvent("keydown", { key: "Enter", bubbles: true })
      )
    JS
  end
end
