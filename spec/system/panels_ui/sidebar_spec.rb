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

  it "temporarily expands over content while hovered and collapses after pointer leave" do
    expect(sidebar["data-collapsed"]).to eq("true")
    expect(page).to have_no_css("#sd-nav-sidebar .panel-sidebar__label", visible: true)
    content_left = page.evaluate_script("document.querySelector('[data-testid=sidebar-demo] > .flex-1').getBoundingClientRect().left")

    sidebar.hover

    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='false'][data-locked='false']")
    expect(page).to have_css("button[aria-controls='sd-nav-sidebar'][aria-expanded='true']")
    expect(page).to have_css("#sd-nav-sidebar .panel-sidebar__label", visible: true, text: "Bookings")
    expect(page.evaluate_script("document.querySelector('[data-testid=sidebar-demo] > .flex-1').getBoundingClientRect().left")).to eq(content_left)

    find("#sidebar-preview-heading").hover

    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='true'][data-locked='false']")
    expect(page).to have_css("button[aria-controls='sd-nav-sidebar'][aria-expanded='false']")
  end

  it "overlays inward without shifting content in RTL" do
    page.execute_script("document.querySelector('[data-testid=sidebar-demo]').dir = 'rtl'")
    content_right = page.evaluate_script("document.querySelector('[data-testid=sidebar-demo] > .flex-1').getBoundingClientRect().right")

    sidebar.hover

    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='false'][data-locked='false']")
    expect(page.evaluate_script("document.querySelector('[data-testid=sidebar-demo] > .flex-1').getBoundingClientRect().right")).to eq(content_right)
  end

  it "does not expand from coarse pointer input" do
    page.execute_script(<<~JS)
      document.querySelector("#sd-nav-sidebar").dispatchEvent(
        new PointerEvent("pointerenter", { pointerType: "touch" })
      )
    JS

    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='true'][data-locked='false']")
  end

  it "stays temporarily expanded while an expanded control has focus" do
    sidebar.hover
    page.execute_script("document.querySelector('#sd-nav-sidebar-search-desktop').focus()")
    find("#sidebar-preview-heading").hover

    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='false'][data-locked='false']")

    page.execute_script("document.querySelector('[data-controller=\"panels-ui--sidebar-toggle\"]').focus()")
    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='true'][data-locked='false']")
  end

  it "locks the desktop sidebar open until the toggle is pressed again" do
    click_button "Toggle lock"

    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='false'][data-locked='true']")
    expect(page).to have_css("button[aria-controls='sd-nav-sidebar'][aria-expanded='true'][aria-pressed='true'][aria-label='Unlock navigation']")
    expect(page).to have_css("[data-sidebar-toggle-icon='unlock']:not([hidden])")

    sidebar.hover
    find("#sidebar-preview-heading").hover
    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='false'][data-locked='true']")

    click_button "Toggle lock"
    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='true'][data-locked='false']")
    expect(page).to have_css("button[aria-pressed='false'][aria-label='Lock navigation open']")
  end

  it "uses the compact Shadcn-like rail and item geometry" do
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

  it "gives collapsed links and group triggers identical default and active states" do
    link = "#sd-nav-sidebar [data-sidebar-presentation='collapsed'] a[href='#arrivals']"
    group = "#sd-nav-sidebar-desktop-section-1-item-2-popover-trigger"

    expect(computed_color(group, "backgroundColor")).to eq(computed_color(link, "backgroundColor"))
    expect(computed_color(group, "color")).to eq(computed_color(link, "color"))

    page.execute_script("document.querySelector(#{group.to_json}).closest('[data-sidebar-group-item]').setAttribute('data-sidebar-active', '')")
    active_link = "#sd-nav-sidebar [data-sidebar-presentation='collapsed'] a[href='/system-design']"
    wait_until("active group trigger did not finish transitioning") do
      computed_color(group, "backgroundColor") == computed_color(active_link, "backgroundColor") &&
        computed_color(group, "color") == computed_color(active_link, "color")
    end
    expect(computed_color(group, "backgroundColor")).to eq(computed_color(active_link, "backgroundColor"))
    expect(computed_color(group, "color")).to eq(computed_color(active_link, "color"))
  end

  it "keeps a locked sidebar open through Turbo rendering and resets after refresh" do
    click_button "Toggle lock"
    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='false'][data-locked='true']")

    page.execute_script(<<~JS)
      document.dispatchEvent(new CustomEvent("turbo:before-render"))
      document.dispatchEvent(new CustomEvent("turbo:load"))
    JS
    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='false'][data-locked='true']")

    page.refresh
    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='true'][data-locked='false']")
  end

  it "filters the nav by search text and shows the empty state when nothing matches" do
    sidebar.hover

    within("#sd-nav-sidebar") do
      fill_in "sd-nav-sidebar-search-desktop", with: "booking"
      expect(page).to have_css("a.panel-sidebar__link", text: "Bookings")
      expect(page).to have_no_css("a.panel-sidebar__link", text: "Arrivals")

      fill_in "sd-nav-sidebar-search-desktop", with: "zzzzz"
      expect(page).to have_css("[data-panels-ui--sidebar-search-target='empty']:not(.hidden)")
    end
  end

  it "toggles an expanded group through the shared collapsible primitive" do
    sidebar.hover
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
    sidebar.hover
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
    sidebar.hover
    expect(find("#sd-nav-sidebar-desktop-section-1-item-2-collapsible-trigger")["aria-expanded"]).to eq("false")
  end

  it "opens a collapsed group through Popover, supports pinning, and closes outside" do
    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='true']")

    trigger = find("#sd-nav-sidebar-desktop-section-1-item-2-popover-trigger")
    panel = "#sd-nav-sidebar-desktop-section-1-item-2-popover-panel"
    open_popover_with_keyboard(trigger)
    expect(page).to have_css("#{panel}:popover-open", text: "Financial")

    find(panel).hover
    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='true']")
    expect(page).to have_css("#{panel}:popover-open", text: "Tax & Compliance")
    arrow_left = page.evaluate_script("document.querySelector('#{panel} .floating-arrow').style.left")
    expect(arrow_left).to match(/-\d/)

    find("#sidebar-preview-heading").hover
    expect(page).to have_css("#{panel}:popover-open", text: "Financial")

    find("#sidebar-preview-heading").click
    expect(page).to have_no_css("#{panel}:popover-open")
  end

  it "shows the shared tooltip for a keyboard-focused collapsed top-level link" do
    page.execute_script("document.querySelector(\"#sd-nav-sidebar [data-sidebar-presentation='collapsed'] a[href='#bookings']\").focus()")

    expect(page).to have_css("#sd-nav-sidebar .tooltip:popover-open", text: "Bookings")
    tooltip = "#sd-nav-sidebar .tooltip:popover-open"
    expect(computed_style(tooltip, "backgroundColor")).not_to eq(computed_style("#sd-nav-sidebar", "backgroundColor"))
    expect(computed_style(tooltip, "borderRadius")).to eq("8px")

    find("#sidebar-preview-heading").click
    expect(page).to have_no_css("#sd-nav-sidebar .tooltip:popover-open", text: "Bookings")
  end

  it "uses the elevated sidebar-only flyout surface" do
    open_popover_with_keyboard(find("#sd-nav-sidebar-desktop-section-1-item-2-popover-trigger"))
    flyout = "#sd-nav-sidebar-desktop-section-1-item-2-popover-panel:popover-open"
    expect(page).to have_css(flyout)

    expect(computed_style(flyout, "backgroundColor")).not_to eq(computed_style("#sd-nav-sidebar", "backgroundColor"))
    expect(computed_style(flyout, "borderRadius")).to eq("8px")
    expect(computed_style(flyout, "borderColor")).not_to eq(computed_style(flyout, "backgroundColor"))
  end

  it "does not show flyouts or tooltips while expanded" do
    sidebar.hover
    find("#sd-nav-sidebar [data-sidebar-presentation='expanded'] a[href='#bookings']").hover
    expect(page).to have_no_css("#sd-nav-sidebar .tooltip:popover-open")
    expect(page).to have_no_css("#sd-nav-sidebar .popover:popover-open")
  end

  it "closes an open flyout when the sidebar presentation changes" do
    trigger = find("#sd-nav-sidebar-desktop-section-1-item-2-popover-trigger")
    panel = "#sd-nav-sidebar-desktop-section-1-item-2-popover-panel"
    open_popover_with_keyboard(trigger)
    expect(page).to have_css("#{panel}:popover-open")

    click_button "Toggle lock"
    expect(page).to have_no_css("#{panel}:popover-open")
    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='false']")
  end

  it "closes a pinned flyout on Escape and restores trigger focus" do
    trigger = find("#sd-nav-sidebar-desktop-section-1-item-2-popover-trigger")
    panel = "#sd-nav-sidebar-desktop-section-1-item-2-popover-panel"
    open_popover_with_keyboard(trigger)
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


  it "keeps non-collapsible navigation expanded and hides its toggle" do
    page.execute_script(<<~JS)
      const sidebar = document.getElementById("sd-nav-sidebar")
      const toggle = document.querySelector("[data-controller='panels-ui--sidebar-toggle']")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(toggle, "panels-ui--sidebar-toggle")
      sidebar.dataset.collapsible = "false"
      controller.disconnect()
      controller.connect()
    JS

    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='false']")
    expect(page).to have_css("#sd-nav-sidebar .panel-sidebar__label", visible: true, text: "Bookings")
    expect(page).to have_css("button[data-controller='panels-ui--sidebar-toggle'][hidden]", visible: :all)
  end

  it "keeps the toggle visible while Turbo restores its permanent sidebar" do
    hidden_without_sidebar = page.evaluate_script(<<~JS)
      (() => {
        const sidebar = document.getElementById("sd-nav-sidebar")
        const parent = sidebar.parentNode
        const nextSibling = sidebar.nextSibling
        const toggle = document.querySelector("[data-controller='panels-ui--sidebar-toggle']")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(toggle, "panels-ui--sidebar-toggle")

        sidebar.remove()
        controller.disconnect()
        controller.connect()
        const hidden = toggle.hidden

        parent.insertBefore(sidebar, nextSibling)
        document.dispatchEvent(new CustomEvent("turbo:load"))
        return hidden
      })()
    JS

    expect(hidden_without_sidebar).to be(false)
    expect(page).to have_css("button[data-controller='panels-ui--sidebar-toggle']:not([hidden])")
    expect(page).to have_css("#sd-nav-sidebar[data-collapsed='true']")
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
