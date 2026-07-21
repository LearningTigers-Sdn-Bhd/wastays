# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::Sidebar", type: :system do
  before { visit_when_loaded "/system-design?only=sidebar_preview" }

  after do
    page.execute_script("window.localStorage.clear()")
    page.execute_script("window.sessionStorage.clear()")
  rescue StandardError
    nil
  end

  let(:sidebar) { find("#sd-nav-sidebar") }

  COLOR_PROPERTIES = %w[backgroundColor color borderColor].freeze

  # Chrome can serialize the same resolved color as either oklch(...) or oklab(...)
  # depending on how the declaring CSS rule computed it (e.g. color-mix() vs a literal
  # value), even though the underlying color is identical. Route color properties
  # through a canvas fillStyle round-trip so both sides normalize to the same rgb notation.
  def computed_style(selector, property)
    value = page.evaluate_script(<<~JS)
      getComputedStyle(document.querySelector(#{selector.to_json}))[#{property.to_json}]
    JS
    return value unless COLOR_PROPERTIES.include?(property)

    page.evaluate_script(<<~JS)
      (function(value) {
        const ctx = document.createElement("canvas").getContext("2d");
        ctx.fillStyle = value;
        return ctx.fillStyle;
      })(#{value.to_json})
    JS
  end

  def computed_color(selector, property)
    page.evaluate_script(<<~JS)
      (() => {
        const canvas = document.createElement("canvas")
        const context = canvas.getContext("2d")
        context.fillStyle = getComputedStyle(document.querySelector(#{selector.to_json}))[#{property.to_json}]
        context.fillRect(0, 0, 1, 1)
        return Array.from(context.getImageData(0, 0, 1, 1).data)
      })()
    JS
  end

  it "marks the item whose path matches the current page as active" do
    within("#sd-nav-sidebar") do
      expect(page).to have_css("a[href='/system-design'][aria-current='page']", count: 2, visible: :all)
    end
  end

  it "cancels an exact same-URL Turbo visit without blocking another destination" do
    result = page.evaluate_script(<<~JS)
      (() => {
        const sameUrlVisit = new CustomEvent("turbo:before-visit", {
          bubbles: true,
          cancelable: true,
          detail: { url: window.location.href }
        })
        const differentUrlVisit = new CustomEvent("turbo:before-visit", {
          bubbles: true,
          cancelable: true,
          detail: { url: `${window.location.origin}/system-design?section=sidebar` }
        })

        document.dispatchEvent(sameUrlVisit)
        document.dispatchEvent(differentUrlVisit)

        return [sameUrlVisit.defaultPrevented, differentUrlVisit.defaultPrevented]
      })()
    JS

    expect(result).to eq([ true, false ])
  end

  it "collapses and expands the desktop sidebar, hiding labels while collapsed" do
    expect(sidebar["data-collapsed"]).to eq("false")

    click_button "Toggle collapse"
    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='true']")
    expect(page).to have_no_css("#sd-nav-sidebar .panel-sidebar__label", visible: true)

    click_button "Toggle collapse"
    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='false']")
    expect(page).to have_css("#sd-nav-sidebar .panel-sidebar__label", visible: true, text: "Bookings")
  end

  it "uses the compact Shadcn-like rail and item geometry" do
    click_button "Toggle collapse"
    wait_until("sidebar did not finish collapsing") { computed_style("#sd-nav-sidebar", "width") == "48px" }
    link = "#sd-nav-sidebar [data-sidebar-presentation='collapsed'] a[href='#arrivals']"
    group = "#sd-nav-sidebar-desktop-section-1-item-2-popover-trigger"

    expect(computed_style("#sd-nav-sidebar", "width")).to eq("48px")
    [ link, group ].each do |selector|
      expect(computed_style(selector, "width")).to eq("32px")
      expect(computed_style(selector, "height")).to eq("32px")
      expect(computed_style(selector, "borderRadius")).to eq("8px")
    end
  end

  it "gives collapsed links and group triggers identical visual states" do
    click_button "Toggle collapse"
    link = "#sd-nav-sidebar [data-sidebar-presentation='collapsed'] a[href='#arrivals']"
    group = "#sd-nav-sidebar-desktop-section-1-item-2-popover-trigger"

    expect(computed_color(group, "backgroundColor")).to eq(computed_color(link, "backgroundColor"))
    expect(computed_color(group, "color")).to eq(computed_color(link, "color"))

    arm_transition_wait(link)
    find(link).hover
    wait_for_transition_end(link)
    link_hover = [ computed_color(link, "backgroundColor"), computed_color(link, "color") ]
    find("#sidebar-preview-heading").hover
    arm_transition_wait(group)
    find(group).hover
    wait_for_transition_end(group)
    group_hover = [ computed_color(group, "backgroundColor"), computed_color(group, "color") ]
    expect(group_hover).to eq(link_hover)

    page.execute_script("document.querySelector(#{group.to_json}).closest('[data-sidebar-group-item]').setAttribute('data-sidebar-active', '')")
    active_link = "#sd-nav-sidebar [data-sidebar-presentation='collapsed'] a[href='/system-design']"
    wait_until("active group trigger did not finish transitioning") do
      computed_color(group, "backgroundColor") == computed_color(active_link, "backgroundColor") &&
        computed_color(group, "color") == computed_color(active_link, "color")
    end
    expect(computed_color(group, "backgroundColor")).to eq(computed_color(active_link, "backgroundColor"))
    expect(computed_color(group, "color")).to eq(computed_color(active_link, "color"))
  end

  it "persists the collapsed state across a reload" do
    click_button "Toggle collapse"
    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='true']")

    visit_when_loaded "/system-design?only=sidebar_preview"
    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='true']")
  end

  it "filters the nav by search text and shows the empty state when nothing matches" do
    within("#sd-nav-sidebar") do
      fill_in "sd-nav-sidebar-search-desktop", with: "booking"
      expect(page).to have_css("a.panel-sidebar__link", text: "Bookings")
      expect(page).to have_no_css("a.panel-sidebar__link", text: "Arrivals")

      fill_in "sd-nav-sidebar-search-desktop", with: "zzzzz"
      expect(page).to have_css("[data-panels-ui--sidebar-search-target='empty']:not(.hidden)")
    end
  end

  it "toggles an expanded group through the shared collapsible primitive" do
    trigger = find("#sd-nav-sidebar-desktop-section-1-item-2-collapsible-trigger")
    content = "#sd-nav-sidebar-desktop-section-1-item-2-collapsible-content"

    expect(trigger["aria-expanded"]).to eq("false")
    trigger.click
    expect(trigger["aria-expanded"]).to eq("true")
    expect(page).to have_css("#{content}:not([hidden])[data-state='open']")
    expect(computed_style(content, "animationName")).to eq("panel-collapsible-down")

    trigger.click
    expect(trigger["aria-expanded"]).to eq("false")
    expect(page).to have_css("#{content}[hidden]", visible: :all, wait: 1)
  end

  it "does not animate server-rendered group state during initial layout" do
    content = "#sd-nav-sidebar-desktop-section-1-item-2-collapsible-content"

    page.execute_script(<<~JS)
      const content = document.querySelector(#{content.to_json})
      content.hidden = false
      content.dataset.state = "open"
      content.removeAttribute("data-collapsible-animate")
    JS

    expect(computed_style(content, "animationName")).to eq("none")
  end

  it "preserves a manually closed group across navigation" do
    trigger = find("#sd-nav-sidebar-desktop-section-1-item-2-collapsible-trigger")
    trigger.click
    expect(trigger["aria-expanded"]).to eq("true")

    trigger.click
    expect(trigger["aria-expanded"]).to eq("false")

    page.execute_script(<<~JS)
      const sidebar = document.querySelector("#sd-nav-sidebar")
      const group = sidebar.querySelector("#sd-nav-sidebar-desktop-section-1-item-2-collapsible")
      group.querySelector("a[data-sidebar-route]").setAttribute("href", window.location.pathname)
      window.Stimulus.getControllerForElementAndIdentifier(sidebar, "panels-ui--sidebar").syncActiveLinks()
    JS
    expect(trigger["aria-expanded"]).to eq("false")

    visit_when_loaded "/system-design?only=sidebar_preview"
    expect(find("#sd-nav-sidebar-desktop-section-1-item-2-collapsible-trigger")["aria-expanded"]).to eq("false")
  end

  it "opens a collapsed group through Popover, supports pinning, and closes outside" do
    click_button "Toggle collapse"
    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='true']")

    trigger = find("#sd-nav-sidebar-desktop-section-1-item-2-popover-trigger")
    panel = "#sd-nav-sidebar-desktop-section-1-item-2-popover-panel"
    trigger.hover
    expect(page).to have_css("#{panel}:popover-open", text: "Financial")

    find(panel).hover
    expect(page).to have_css("#{panel}:popover-open", text: "Tax & Compliance")
    arrow_left = page.evaluate_script("document.querySelector('#{panel} .floating-arrow').style.left")
    expect(arrow_left).to match(/-\d/)

    trigger.click
    find("#sidebar-preview-heading").hover
    expect(page).to have_css("#{panel}:popover-open", text: "Financial")

    find("#sidebar-preview-heading").click
    expect(page).to have_no_css("#{panel}:popover-open")
  end

  it "shows the shared tooltip only for a collapsed top-level link" do
    click_button "Toggle collapse"
    find("#sd-nav-sidebar [data-sidebar-presentation='collapsed'] a[href='#bookings']").hover

    expect(page).to have_css("#sd-nav-sidebar .tooltip:popover-open", text: "Bookings")
    tooltip = "#sd-nav-sidebar .tooltip:popover-open"
    expect(computed_style(tooltip, "backgroundColor")).not_to eq(computed_style("#sd-nav-sidebar", "backgroundColor"))
    expect(computed_style(tooltip, "borderRadius")).to eq("8px")

    find("#sidebar-preview-heading").hover
    expect(page).to have_no_css("#sd-nav-sidebar .tooltip:popover-open", text: "Bookings")
  end

  it "uses the elevated sidebar-only flyout surface" do
    click_button "Toggle collapse"
    find("#sd-nav-sidebar-desktop-section-1-item-2-popover-trigger").click
    flyout = "#sd-nav-sidebar-desktop-section-1-item-2-popover-panel:popover-open"
    expect(page).to have_css(flyout)

    expect(computed_style(flyout, "backgroundColor")).not_to eq(computed_style("#sd-nav-sidebar", "backgroundColor"))
    expect(computed_style(flyout, "borderRadius")).to eq("8px")
    expect(computed_style(flyout, "borderColor")).not_to eq(computed_style(flyout, "backgroundColor"))
  end

  it "does not show flyouts or tooltips while expanded" do
    find("#sd-nav-sidebar [data-sidebar-presentation='expanded'] a[href='#bookings']").hover
    expect(page).to have_no_css("#sd-nav-sidebar .tooltip:popover-open")
    expect(page).to have_no_css("#sd-nav-sidebar .popover:popover-open")
  end

  it "closes an open flyout when the sidebar presentation changes" do
    click_button "Toggle collapse"
    trigger = find("#sd-nav-sidebar-desktop-section-1-item-2-popover-trigger")
    panel = "#sd-nav-sidebar-desktop-section-1-item-2-popover-panel"
    trigger.click
    expect(page).to have_css("#{panel}:popover-open")

    click_button "Toggle collapse"
    expect(page).to have_no_css("#{panel}:popover-open")
    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='false']")
  end

  it "closes a pinned flyout on Escape and restores trigger focus" do
    click_button "Toggle collapse"
    trigger = find("#sd-nav-sidebar-desktop-section-1-item-2-popover-trigger")
    panel = "#sd-nav-sidebar-desktop-section-1-item-2-popover-panel"
    trigger.click
    expect(page).to have_css("#{panel}:popover-open")

    page.send_keys(:escape)
    expect(page).to have_no_css("#{panel}:popover-open")
    expect(page.evaluate_script("document.activeElement.id")).to eq(trigger[:id])
  end

  it "persists and restores the navigation scroll position" do
    page.execute_script(<<~JS)
      const body = document.querySelector("#sd-nav-sidebar .panel-sidebar__body")
      body.style.height = "40px"
      body.style.flex = "none"
      body.scrollTop = 30
      document.dispatchEvent(new CustomEvent("turbo:before-visit"))
      body.scrollTop = 0
      document.dispatchEvent(new CustomEvent("turbo:load"))
    JS

    expect(page.evaluate_script("document.querySelector('#sd-nav-sidebar .panel-sidebar__body').scrollTop")).to eq(30)
  end

  it "uses Sheet for the mobile drawer and restores focus after Escape" do
    page.current_window.resize_to(390, 844)
    original_overflow = page.evaluate_script("document.body.style.overflow")

    click_button "Open mobile navigation"

    expect(page).to have_css("dialog#sd-nav-sidebar-mobile[open][data-panels-open]")
    expect(page.evaluate_script("document.activeElement.closest('dialog')?.id")).to eq("sd-nav-sidebar-mobile")
    expect(page.evaluate_script("document.body.style.overflow")).to eq("hidden")

    find("dialog#sd-nav-sidebar-mobile").send_keys(:escape)

    expect(page).to have_no_css("dialog#sd-nav-sidebar-mobile[open]")
    expect(page.evaluate_script("document.activeElement.id")).to eq("sd-nav-sidebar-mobile-trigger")
    expect(page.evaluate_script("document.body.style.overflow")).to eq(original_overflow)
  end

  it "closes the mobile Sheet from its close button and backdrop" do
    page.current_window.resize_to(390, 844)
    arm_transition_wait("#sd-nav-sidebar-mobile", property: "translate")
    click_button "Open mobile navigation"
    wait_for_transition_end("#sd-nav-sidebar-mobile")
    page.execute_script(<<~JS)
      document.querySelector(
        "#sd-nav-sidebar-mobile button[aria-label='Close navigation']"
      ).click()
    JS
    expect(page).to have_no_css("dialog#sd-nav-sidebar-mobile[open]")

    click_button "Open mobile navigation"
    page.execute_script(<<~JS)
      document.getElementById("sd-nav-sidebar-mobile").dispatchEvent(
        new MouseEvent("click", { bubbles: true })
      )
    JS
    expect(page).to have_no_css("dialog#sd-nav-sidebar-mobile[open]")
  end

  it "persists desktop and mobile scroll positions independently" do
    page.execute_script(<<~JS)
      const desktop = document.querySelector("#sd-nav-sidebar .panel-sidebar__body")
      desktop.style.height = "40px"
      desktop.style.flex = "none"
      desktop.scrollTop = 20
      document.dispatchEvent(new CustomEvent("turbo:before-visit"))
    JS

    page.current_window.resize_to(390, 844)
    click_button "Open mobile navigation"
    page.execute_script(<<~JS)
      const mobile = document.querySelector("#sd-nav-sidebar-mobile .panel-sidebar__body")
      mobile.style.height = "40px"
      mobile.style.flex = "none"
      mobile.scrollTop = 30
      document.dispatchEvent(new CustomEvent("turbo:before-visit"))
      mobile.scrollTop = 0
    JS

    expect(page.evaluate_script("sessionStorage.getItem('wastays:sd-nav-sidebar-desktop-scroll-top')")).to eq("20")
    expect(page.evaluate_script("sessionStorage.getItem('wastays:sd-nav-sidebar-mobile-scroll-top')")).to eq("30")

    find("dialog#sd-nav-sidebar-mobile").send_keys(:escape)
    page.current_window.resize_to(1280, 900)
    page.execute_script(<<~JS)
      const desktop = document.querySelector("#sd-nav-sidebar .panel-sidebar__body")
      desktop.scrollTop = 0
      document.dispatchEvent(new CustomEvent("turbo:load"))
    JS
    expect(page.evaluate_script("document.querySelector('#sd-nav-sidebar .panel-sidebar__body').scrollTop")).to eq(20)

    page.current_window.resize_to(390, 844)
    click_button "Open mobile navigation"
    expect(page.evaluate_script("document.querySelector('#sd-nav-sidebar-mobile .panel-sidebar__body').scrollTop")).to eq(30)
  end


  it "ignores desktop collapse requests when collapsing is disabled" do
    page.execute_script("document.getElementById('sd-nav-sidebar').dataset.collapsible = 'false'")

    click_button "Toggle collapse"

    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='false']")
  end

  it "cleans up mobile scroll locking after Turbo-style removal" do
    page.current_window.resize_to(390, 844)
    original_overflow = page.evaluate_script("document.body.style.overflow")
    click_button "Open mobile navigation"
    expect(page.evaluate_script("document.body.style.overflow")).to eq("hidden")

    page.execute_script("document.getElementById('sd-nav-sidebar-mobile').remove()")

    expect(page).to have_no_css("#sd-nav-sidebar-mobile")
    expect(page.evaluate_script("document.body.style.overflow")).to eq(original_overflow)
  end
end
