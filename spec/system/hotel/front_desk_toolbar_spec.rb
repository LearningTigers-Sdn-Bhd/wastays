require "rails_helper"

RSpec.describe "Hotel front desk toolbar", type: :system, js: true do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account, slug: "hotel_owner", name: "Hotel Owner") }

  before do
    driven_by(:cuprite)

    %w[view_bookings manage_guest_arrival].each do |slug|
      permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.titleize }
      RolePermission.find_or_create_by!(role: role, permission: permission)
    end
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)
    visit hotel_front_desk_path(
      hotel,
      tab: "arrivals",
      view: "list",
      arrival_start_date: "2026-07-15",
      arrival_end_date: "2026-07-16"
    )
    expect(page).to have_css("[data-controller~='front-desk-date-range'] [data-enhanced='true']", wait: 10)
  end

  it "keeps old dates for an incomplete range then submits one complete scoped range" do
    incomplete = page.evaluate_script(<<~JS)
      (() => {
        sessionStorage.setItem("frontDeskSubmitCount", "0")
        const form = document.querySelector("form[action*='front-desk']")
        form.addEventListener("submit", () => {
          const count = Number(sessionStorage.getItem("frontDeskSubmitCount"))
          sessionStorage.setItem("frontDeskSubmitCount", String(count + 1))
        })
        const calendar = form.querySelector("calendar-range")
        calendar.value = "2026-07-20"
        calendar.dispatchEvent(new Event("change", { bubbles: true }))
        return {
          start: form.querySelector("input[name='arrival_start_date']").value,
          end: form.querySelector("input[name='arrival_end_date']").value,
          submits: Number(sessionStorage.getItem("frontDeskSubmitCount"))
        }
      })()
    JS

    expect(incomplete).to eq("start" => "2026-07-15", "end" => "2026-07-16", "submits" => 0)

    page.execute_script(<<~JS)
      (() => {
        const calendar = document.querySelector("form[action*='front-desk'] calendar-range")
        calendar.value = "2026-07-20/2026-07-22"
        calendar.dispatchEvent(new Event("change", { bubbles: true }))
      })()
    JS

    expect(page).to have_current_path(
      /arrival_start_date=2026-07-20.*arrival_end_date=2026-07-22/,
      url: true,
      wait: 10
    )
    expect(page.current_url).not_to include("front_desk_date_range")
    expect(page.evaluate_script('Number(sessionStorage.getItem("frontDeskSubmitCount"))')).to eq(1)
  end

  it "renders view buttons and date trigger at equal heights" do
    heights = page.evaluate_script(<<~JS)
      (() => {
        const toolbar = document.querySelector("form[action*='front-desk']")
        const viewButtons = toolbar.querySelectorAll("[aria-label='Reservation view'] .panel-button")
        const dateTrigger = toolbar.querySelector(".panel-date-picker__display")
        return {
          rooms: viewButtons[0].getBoundingClientRect().height,
          list: viewButtons[1].getBoundingClientRect().height,
          date: dateTrigger.getBoundingClientRect().height
        }
      })()
    JS

    expect(heights.values.uniq).to contain_exactly(36)
  end

  it "cancels pending search submission when a complete range submits" do
    page.execute_script(<<~JS)
      sessionStorage.setItem("frontDeskSubmitCount", "0")
      document.addEventListener("submit", () => {
        const count = Number(sessionStorage.getItem("frontDeskSubmitCount"))
        sessionStorage.setItem("frontDeskSubmitCount", String(count + 1))
      }, true)
      let delayed = false
      window.__delayedResumeFired = false
      document.addEventListener("turbo:before-fetch-request", event => {
        if (delayed) return

        delayed = true
        event.preventDefault()
        setTimeout(() => {
          event.detail.resume()
          window.__delayedResumeFired = true
        }, 600)
      }, true)

      const form = document.querySelector("form[action*='front-desk']")
      const search = form.querySelector("input[name='arrival_q']")
      search.value = "Race"
      search.dispatchEvent(new Event("input", { bubbles: true }))

      const calendar = form.querySelector("calendar-range")
      calendar.value = "2026-07-20/2026-07-22"
      calendar.dispatchEvent(new Event("change", { bubbles: true }))
    JS

    expect(page).to have_current_path(/arrival_q=Race/, url: true, wait: 10)
    wait_until("expected the delayed, superseded request to finish resolving") do
      page.evaluate_script("window.__delayedResumeFired")
    end
    expect(page.current_url).to include("arrival_start_date=2026-07-20", "arrival_end_date=2026-07-22")
    expect(page.current_url).not_to include("front_desk_date_range")
    expect(page.evaluate_script('Number(sessionStorage.getItem("frontDeskSubmitCount"))')).to eq(1)
  end

  it "syncs a complete internal range before non-calendar form cleanup" do
    page.execute_script(<<~JS)
      const form = document.querySelector("form[action*='front-desk']")
      form.querySelector("input[name='front_desk_date_range']").value = "2026-07-24/2026-07-26"
      form.querySelector("input[name='arrival_start_date']").value = ""
      form.querySelector("input[name='arrival_end_date']").value = ""
      const search = form.querySelector("input[name='arrival_q']")
      search.value = "Manual"
      form.requestSubmit()
    JS

    expect(page).to have_current_path(/arrival_q=Manual/, url: true, wait: 10)
    expect(page.current_url).to include("arrival_start_date=2026-07-24", "arrival_end_date=2026-07-26")
    expect(page.current_url).not_to include("front_desk_date_range")
  end

  it "submits one range after Turbo reconnect" do
    click_link "Rooms"
    expect(page).to have_current_path(/view=rooms/, url: true, wait: 10)
    expect(page).to have_css("[data-controller~='front-desk-date-range'] [data-enhanced='true']", wait: 10)

    page.execute_script(<<~JS)
      sessionStorage.setItem("frontDeskSubmitCount", "0")
      document.addEventListener("submit", () => {
        const count = Number(sessionStorage.getItem("frontDeskSubmitCount"))
        sessionStorage.setItem("frontDeskSubmitCount", String(count + 1))
      }, true)
      const calendar = document.querySelector("form[action*='front-desk'] calendar-range")
      calendar.value = "2026-07-28/2026-07-30"
      calendar.dispatchEvent(new Event("change", { bubbles: true }))
    JS

    expect(page).to have_current_path(/arrival_start_date=2026-07-28.*arrival_end_date=2026-07-30/, url: true, wait: 10)
    expect(page.evaluate_script('Number(sessionStorage.getItem("frontDeskSubmitCount"))')).to eq(1)
  end

  it "cancels both re-enable timers when Turbo disconnects after immediate submissions" do
    pending_timers = page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      const nativeSetTimeout = window.setTimeout
      const nativeClearTimeout = window.clearTimeout
      const pending = new Map()
      let captureTimers = false
      let nextTimer = 1

      window.setTimeout = (callback, delay, ...args) => {
        if (!captureTimers || delay !== 0) return nativeSetTimeout(callback, delay, ...args)

        const timer = nextTimer++
        pending.set(timer, () => callback(...args))
        return timer
      }
      window.clearTimeout = timer => pending.delete(timer) || nativeClearTimeout(timer)

      const form = document.querySelector("form[action*='front-desk']")
      form.addEventListener("submit", event => event.preventDefault())
      captureTimers = true
      form.requestSubmit()
      form.requestSubmit()
      captureTimers = false

      document.addEventListener("turbo:load", () => {
        window.setTimeout = nativeSetTimeout
        window.clearTimeout = nativeClearTimeout
        done(pending.size)
      }, { once: true })
      Turbo.visit(document.querySelector("a[href*='view=rooms']").href)
    JS

    expect(pending_timers).to eq(0)
  end
end
