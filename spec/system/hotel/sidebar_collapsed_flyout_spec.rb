# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel collapsed sidebar flyout", type: :system do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, account: account, plan: plan, status: "approved") }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account) }

  before do
    driven_by(:cuprite)

    permission = Permission.find_by(slug: "view_reports") ||
      create(:permission, name: "View Reports", slug: "view_reports")
    create(:role_permission, role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)
    visit hotel_reports_path(hotel)
  end

  it "shows instant tooltips and hover-opened report children in a compact rail" do
    find('button[aria-label="Collapse sidebar"]').click

    expect(page).to have_css("#hotel-sidebar.sidebar-collapsed")
    compact_section_spacing = page.evaluate_script(<<~JS)
      (() => {
        const groups = Array.from(document.querySelectorAll("#hotel-sidebar .sidebar-nav-group"))
          const styles = window.getComputedStyle(groups[0])
        return parseFloat(styles.marginTop) + parseFloat(styles.paddingTop)
      })()
    JS
    expect(compact_section_spacing).to be <= 8

    within("#hotel-sidebar") do
      expect(page).to have_no_css("details.sidebar-group[open]")

      help_link = find("a[data-sidebar-tooltip='Help & support']", visible: :all)
      help_link.hover

      expect(page).to have_css(".sidebar-tooltip", text: "Help & support", visible: :visible)
      expect(page).to have_no_css("a[data-sidebar-tooltip='Help & support'][title]", visible: :all)

      financial_group = find("summary.sidebar-group-parent", text: "Financial", visible: :all)
      financial_group.hover

      expect(page).to have_css("details.sidebar-group[open] > summary[aria-label='Financial']")
      expect(page).to have_css(".sidebar-details-content[style*='left:']")
      expect(page).to have_no_css(".sidebar-tooltip", visible: :visible)

      summary_link = find("a.sidebar-child-link[aria-label='Summary']", visible: :all)
      summary_link.hover

      expect(page).to have_css(".sidebar-tooltip", text: "Summary", visible: :visible)
      expect(page).to have_css("a.sidebar-child-link[aria-label='Summary']", visible: :all)
      expect(page).to have_css("a.sidebar-child-link span.hidden", text: "Summary", visible: :all)
    end

    find("main").hover

    within("#hotel-sidebar") do
      expect(page).to have_no_css("details.sidebar-group[open]")
      expect(page).to have_no_css(".sidebar-tooltip", visible: :visible)
    end
  end

  xit "pins a clicked group until it is dismissed" do
    find('button[aria-label="Collapse sidebar"]').click

    within("#hotel-sidebar") do
      find("summary.sidebar-group-parent", text: "Financial", visible: :all).click

      expect(page).to have_css("details.sidebar-group-active[open][data-sidebar-pinned='true']")
    end

    find("main").hover

    within("#hotel-sidebar") do
      expect(page).to have_css("details.sidebar-group-active[open][data-sidebar-pinned='true']")

      find("summary.sidebar-group-parent", text: "Financial", visible: :all).hover
    end

    find("main").hover

    within("#hotel-sidebar") do
      expect(page).to have_css("details.sidebar-group-active[open][data-sidebar-pinned='true']")
    end

    page.send_keys(:escape)

    within("#hotel-sidebar") do
      expect(page).to have_no_css("details.sidebar-group[open]")
    end

    find('button[aria-label="Collapse sidebar"]').click

    within("#hotel-sidebar") do
      expect(page).to have_css("details.sidebar-group-active[open]")
    end
  end

  it "renders report flyout leaves directly in a compact rail, without a wrapping Reports group" do
    find('button[aria-label="Collapse sidebar"]').click

    within("#hotel-sidebar") do
      find("summary.sidebar-group-parent", text: "Financial", visible: :all).click
      expect(page).to have_css("details.sidebar-group[open] > summary[aria-label='Financial']")
      expect(page).to have_no_css("summary.sidebar-group-parent", text: "Reports", visible: :all)
      expect(page).to have_no_css("details.sidebar-group details.sidebar-group", visible: :all)
      expect(page).to have_css("a.sidebar-child-link[aria-label='Summary']", visible: :all)
    end
  end

  it "closes compact rail flyouts on Escape" do
    find('button[aria-label="Collapse sidebar"]').click

    within("#hotel-sidebar") do
      find("summary.sidebar-group-parent", text: "Financial", visible: :all).click

      expect(page).to have_css("details.sidebar-group[open] > summary[aria-label='Financial']")
    end

    page.send_keys(:escape)

    within("#hotel-sidebar") do
      expect(page).to have_no_css("details.sidebar-group[open]", visible: :all)
    end
  end

  it "keeps the most-specific parent route active on nested pages" do
    nested_report_path = "#{hotel_reports_path(hotel)}/nested"

    page.execute_script(<<~JS)
      window.history.pushState({}, "", "#{nested_report_path}")
      document.dispatchEvent(new Event("turbo:load"))
    JS

    within("#hotel-sidebar") do
      expect(page).to have_css("a.panel-sidebar__child[aria-current='page']", text: "Summary")
      expect(page).to have_css("[data-sidebar-group-item][data-sidebar-active] .panel-sidebar__group[data-state='open']")
    end
  end

  it "keeps active and user-opened groups expanded through Turbo navigation" do
    within("#hotel-sidebar") do
      expect(page).to have_css("[data-sidebar-group-item][data-sidebar-active] button.panel-sidebar__group-trigger[aria-expanded='true']", text: "Financial")
      find("button.panel-sidebar__group-trigger", text: "Accounting", visible: :all).click
      expect(page).to have_css("button.panel-sidebar__group-trigger[aria-expanded='true']", text: "Accounting")
    end

    page.execute_script(<<~JS)
      document.addEventListener("turbo:before-visit", () => {
        window.sidebarActiveGroupOpenBeforeVisit =
          document.querySelector("#hotel-sidebar [data-sidebar-group-item][data-sidebar-active] .panel-sidebar__group-trigger")?.getAttribute("aria-expanded") === "true"
      }, { once: true })
    JS

    within("#hotel-sidebar") do
      click_link "Refund Report"
    end

    expect(page).to have_current_path(refund_report_hotel_reports_path(hotel))
    expect(page.evaluate_script("window.sidebarActiveGroupOpenBeforeVisit")).to be(true)

    within("#hotel-sidebar") do
      expect(page).to have_css("a.panel-sidebar__child[aria-current='page']", text: "Refund Report")
      expect(page).to have_css("[data-sidebar-group-item][data-sidebar-active] button.panel-sidebar__group-trigger[aria-expanded='true']", text: "Financial")
      expect(page).to have_css("button.panel-sidebar__group-trigger[aria-expanded='true']", text: "Accounting")
    end
  end
end
