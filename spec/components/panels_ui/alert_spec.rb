# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Alert, type: :component do
  it "renders its title, slots, semantic tone, and default icon" do
    render_inline(described_class.new(tone: :success, title: "Saved")) do |alert|
      alert.with_description { "The booking was updated." }
      alert.with_actions { '<a href="/bookings">View</a>'.html_safe }
    end

    expect(page).to have_css(".panel-alert[role='status'][data-tone='success'][data-has-title='true']")
    expect(page).to have_css(".panel-alert__title", text: "Saved")
    expect(page).to have_css(".panel-alert__description", text: "The booking was updated.")
    expect(page).to have_link("View", href: "/bookings")
    expect(page).to have_css(".panel-alert__icon svg")
  end

  it "supports a custom icon and caller HTML attributes" do
    render_inline(described_class.new(class: "mt-4", id: "custom-alert", aria: { live: "assertive" }, data: { testid: "alert" })) do |alert|
      alert.with_icon { '<span class="custom-icon">!</span>'.html_safe }
      alert.with_description { "Custom" }
    end

    alert = page.find("#custom-alert.panel-alert.mt-4[data-testid='alert'][aria-live='assertive']")
    expect(alert).to have_css(".custom-icon", text: "!")
    expect(alert).to have_css(".panel-alert__icon svg", count: 0)
  end

  it "can omit the icon and title" do
    render_inline(described_class.new(show_icon: false)) do |alert|
      alert.with_description { "Description only" }
    end

    expect(page).to have_no_css(".panel-alert__icon")
    expect(page).to have_no_css(".panel-alert__title")
    expect(page).to have_css(".panel-alert[data-has-title='false']")
    expect(page).to have_css(".panel-alert__description", text: "Description only")
  end

  it "renders accessible dismissal behavior only when requested" do
    render_inline(described_class.new(dismissible: true, title: "Dismiss me"))

    expect(page).to have_css(".panel-alert[data-controller='panels-ui--dismissible']")
    expect(page).to have_css("button[aria-label='Dismiss alert']")
    expect(page).to have_css("button[data-action='panels-ui--dismissible#dismiss']")
  end

  it "falls back to the default tone" do
    render_inline(described_class.new(tone: :unknown, title: "Fallback"))

    expect(page).to have_css(".panel-alert[data-tone='default']")
    expect(page).to have_no_css("button[aria-label='Dismiss alert']")
  end
end
