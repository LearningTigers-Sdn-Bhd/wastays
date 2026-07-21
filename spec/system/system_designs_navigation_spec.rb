# frozen_string_literal: true

require "rails_helper"

RSpec.describe "System design navigation", type: :system do
  it "preserves a deep-linked preview near the end of the page" do
    page.current_window.resize_to(1280, 900)
    visit_when_loaded "/system-design#toast-preview"

    expect(page).to have_css("a[href='#toast-preview'][aria-current='location']", count: 2, visible: :all)
    page.execute_script(<<~JS)
      const root = document.querySelector("[data-controller~='system-designs--preview-navigation']")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(
        root,
        "system-designs--preview-navigation"
      )
      controller.navigationDeadline = 0
      window.dispatchEvent(new Event("scrollend"))
      window.dispatchEvent(new Event("scroll"))
    JS

    expect(page).to have_current_path(%r{/system-design#toast-preview$}, url: true)
    expect(page).to have_css("a[href='#toast-preview'][aria-current='location']", count: 2, visible: :all)
  end

  it "tracks the visible preview in both navigation menus and the URL" do
    page.current_window.resize_to(1280, 900)
    visit_when_loaded "/system-design"
    page.execute_script('window.history.replaceState({ ...window.history.state, sentinel: "preserved" }, "", window.location.href)')

    page.execute_script("document.getElementById('table-preview').scrollIntoView({ block: 'start' })")

    expect(page).to have_current_path(%r{/system-design#table-preview$}, url: true)
    expect(page).to have_css("a[href='#table-preview'][aria-current='location']", count: 2, visible: :all)
    expect(page).to have_no_css("a[href='#alert-preview'][aria-current]", visible: :all)
    expect(page.evaluate_script("window.history.state.sentinel")).to eq("preserved")
  end

  it "keeps the active desktop link visible near the end of the catalogue" do
    page.current_window.resize_to(1280, 900)
    visit_when_loaded "/system-design"

    page.execute_script("document.getElementById('tooltip-preview').scrollIntoView({ block: 'start' })")

    active_link = find("aside a[href='#tooltip-preview'][aria-current='location']")
    navigation = find("aside nav[aria-label='Component previews'][data-active-anchor='tooltip-preview']")
    geometry = page.evaluate_script(<<~JS)
      (() => {
        const navigation = document.querySelector("aside nav[aria-label='Component previews']")
        const link = navigation.querySelector("a[aria-current='location']")
        const navigationRect = navigation.getBoundingClientRect()
        const linkRect = link.getBoundingClientRect()
        return {
          scrollTop: navigation.scrollTop,
          linkTop: linkRect.top,
          linkBottom: linkRect.bottom,
          navigationTop: navigationRect.top,
          navigationBottom: navigationRect.bottom
        }
      })()
    JS

    expect(active_link).to be_present
    expect(navigation).to be_present
    expect(geometry.fetch("scrollTop")).to be_positive
    expect(geometry.fetch("linkTop")).to be >= geometry.fetch("navigationTop")
    expect(geometry.fetch("linkBottom")).to be <= geometry.fetch("navigationBottom")
  end

  it "reveals the active link when the desktop navigation appears after a resize" do
    page.current_window.resize_to(390, 844)
    visit_when_loaded "/system-design"
    page.execute_script("document.getElementById('tooltip-preview').scrollIntoView({ block: 'start' })")
    expect(page).to have_current_path(%r{/system-design#tooltip-preview$}, url: true)

    page.current_window.resize_to(1280, 900)

    navigation = find("aside nav[aria-label='Component previews'][data-active-anchor='tooltip-preview']")
    expect(navigation).to be_present
    expect(page.evaluate_script("document.querySelector(\"aside nav[aria-label='Component previews']\").scrollTop")).to be_positive
  end

  it "closes the mobile component menu after choosing a preview" do
    page.current_window.resize_to(390, 844)
    visit_when_loaded "/system-design"

    menu = find("details[data-system-designs--preview-navigation-target='mobileMenu']")
    menu.find("summary", text: "Components").click
    expect(menu["open"]).to be_present

    menu.click_link("Toast")

    expect(page).to have_current_path(%r{/system-design#toast-preview$}, url: true)
    expect(page).to have_no_css("details[data-system-designs--preview-navigation-target='mobileMenu'][open]")
    expect(page.evaluate_script("document.activeElement.id")).to eq("toast-preview")
    geometry = page.evaluate_script(<<~JS)
      (() => {
        const menu = document.querySelector("details[data-system-designs--preview-navigation-target='mobileMenu']")
        const target = document.getElementById("toast-preview")
        return { menuBottom: menu.getBoundingClientRect().bottom, targetTop: target.getBoundingClientRect().top }
      })()
    JS
    expect(geometry.fetch("targetTop")).to be >= geometry.fetch("menuBottom")
  end

  it "restores the active preview during browser history navigation" do
    page.current_window.resize_to(1280, 900)
    visit_when_loaded "/system-design#alert-preview"
    expect(page).to have_css("aside a[href='#alert-preview'][aria-current='location']")

    within("aside nav[aria-label='Component previews']") { click_link "Toast" }
    expect(page).to have_current_path(%r{/system-design#toast-preview$}, url: true)

    page.go_back

    expect(page).to have_current_path(%r{/system-design#alert-preview$}, url: true)
    expect(page).to have_css("a[href='#alert-preview'][aria-current='location']", count: 2, visible: :all)
  end

  it "renders the timeline preview with responsive overflow and keyboard-accessible stays" do
    page.current_window.resize_to(390, 844)
    visit_when_loaded "/system-design#timeline-preview"

    expect(page).to have_css("section[data-theme='panel-light'] #timeline-preview-panel-light")
    expect(page).to have_css("section[data-theme='panel-dark'] #timeline-preview-panel-dark")
    expect(page).to have_css(".panel-timeline__segment[data-emphasis='hatched']", visible: :all)
    expect(page).to have_css(
      "a#timeline-preview-booking-ada-panel-light-trigger[aria-label='Ada Lovelace, confirmed, room 101, Deluxe King, 20 July 2026 to 21 July 2026']",
      text: "Ada Lovelace",
      visible: :all
    )

    geometry = page.evaluate_script(<<~JS)
      (() => {
        const timeline = document.getElementById("timeline-preview-panel-light")
        const header = timeline.querySelector(".panel-timeline__header")
        const room = timeline.querySelector(".panel-timeline__room-summary")
        const grace = timeline.querySelector("#timeline-preview-booking-grace-panel-light").getBoundingClientRect()
        const ada = timeline.querySelector("#timeline-preview-booking-ada-panel-light").getBoundingClientRect()
        return {
          overflows: timeline.scrollWidth > timeline.clientWidth,
          sequentialStaysDoNotOverlap: grace.right <= ada.left,
          timelinePosition: getComputedStyle(timeline).position,
          headerPosition: getComputedStyle(header).position,
          roomPosition: getComputedStyle(room).position
        }
      })()
    JS

    expect(geometry).to include(
      "overflows" => true,
      "sequentialStaysDoNotOverlap" => true,
      "timelinePosition" => "relative",
      "headerPosition" => "sticky",
      "roomPosition" => "sticky"
    )

    page.execute_script("document.getElementById('timeline-preview-panel-light').focus()")
    target_id = "timeline-preview-booking-grace-panel-light-trigger"
    10.times do
      page.driver.browser.keyboard.type(:tab)
      break if page.evaluate_script("document.activeElement.id") == target_id
    end
    expect(page.evaluate_script("document.activeElement.id")).to eq(target_id)
  end
end
