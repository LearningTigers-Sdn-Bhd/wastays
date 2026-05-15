require "rails_helper"

RSpec.describe "Explore date range picker", type: :system do
  it "keeps the open calendar anchored below the check-in and check-out trigger while scrolling" do
    visit explore_path

    trigger_selector = "[data-controller='date-range-picker']"
    find(trigger_selector).click

    expect(page).to have_text("Clear", wait: 5)
    expect(calendar_is_anchored_to_trigger?(trigger_selector)).to eq(true)

    initial_gap = calendar_trigger_gap(trigger_selector)
    expect(initial_gap).to be_present

    page.execute_script("window.scrollBy(0, 160)")

    expect(wait_for_calendar_gap(trigger_selector, initial_gap)).to be_within(2).of(initial_gap)
  end

  it "closes the calendar when the check-in and check-out trigger is clicked again" do
    visit explore_path

    trigger_selector = "[data-controller='date-range-picker']"
    find(trigger_selector).click

    expect(page).to have_text("Clear", wait: 5)

    find(trigger_selector).click

    expect(calendar_panel_visible?).to eq(false)
  end

  def calendar_panel_visible?
    page.evaluate_script(<<~JS)
      (() => {
        const calendar = document.querySelector("[data-date-range-picker-panel]");
        return Boolean(calendar && !calendar.classList.contains("hidden"));
      })()
    JS
  end

  def calendar_is_anchored_to_trigger?(trigger_selector)
    page.evaluate_script(<<~JS)
      (() => {
        const trigger = document.querySelector("#{trigger_selector}");
        const calendar = findCalendar();

        if (!trigger || !calendar) return false;

        return trigger.contains(calendar) &&
          window.getComputedStyle(calendar).position === "absolute";

        function findCalendar() {
          return Array.from(document.querySelectorAll("[data-date-range-picker-panel]")).find((el) => {
            return !el.classList.contains("hidden") && el.textContent.includes("Clear");
          });
        }
      })()
    JS
  end

  def calendar_trigger_gap(trigger_selector)
    page.evaluate_script(<<~JS)
      (() => {
        const trigger = document.querySelector("#{trigger_selector}");
        const calendar = Array.from(document.querySelectorAll("[data-date-range-picker-panel]")).find((el) => {
          return !el.classList.contains("hidden") && el.textContent.includes("Clear");
        });

        if (!trigger || !calendar) return null;

        const triggerRect = trigger.getBoundingClientRect();
        const calendarRect = calendar.getBoundingClientRect();

        return Math.round(calendarRect.top - triggerRect.bottom);
      })()
    JS
  end

  def wait_for_calendar_gap(trigger_selector, expected_gap)
    Capybara.using_wait_time(5) do
      Timeout.timeout(Capybara.default_max_wait_time) do
        loop do
          gap = calendar_trigger_gap(trigger_selector)
          return gap if gap && (gap - expected_gap).abs <= 2

          sleep 0.05
        end
      end
    end
  rescue Timeout::Error
    calendar_trigger_gap(trigger_selector)
  end
end
