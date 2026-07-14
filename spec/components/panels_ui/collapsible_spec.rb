# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Collapsible, type: :component do
  def render_collapsible(**options)
    render_inline(described_class.new(**{ id: "booking-details" }.merge(options))) do |collapsible|
      collapsible.with_trigger { "Booking details" }
      collapsible.with_body { '<a href="#guest">Guest profile</a>'.html_safe }
    end
  end

  it "wires the native trigger to its content" do
    render_collapsible

    expect(page).to have_css("#booking-details.panel-collapsible[data-controller='panels-ui--collapsible'][data-state='closed']")
    expect(page).to have_css("button#booking-details-trigger[type='button'][aria-expanded='false'][aria-controls='booking-details-content']", text: "Booking details")
    expect(page).to have_css("#booking-details-content.panel-collapsible__content[hidden][inert][data-state='closed']", visible: :all)
    expect(page).to have_link("Guest profile", visible: :all)
  end

  it "renders an initially open disclosure" do
    render_collapsible(open: true)

    expect(page).to have_css("#booking-details[data-panels-ui--collapsible-open-value='true'][data-state='open']")
    expect(page).to have_css("#booking-details-trigger[aria-expanded='true'][data-state='open']")
    expect(page).to have_css("#booking-details-content:not([hidden]):not([inert])[data-state='open']")
  end

  it "renders a disabled trigger and state hooks" do
    render_collapsible(disabled: true)

    expect(page).to have_css("#booking-details[data-disabled][data-panels-ui--collapsible-disabled-value='true']")
    expect(page).to have_css("#booking-details-trigger[disabled][data-disabled]")
    expect(page).to have_css("#booking-details-content[data-disabled]", visible: :all)
  end

  it "merges caller classes, attributes, and controllers" do
    render_collapsible(
      class: "mt-4",
      trigger_class: "px-3",
      content_class: "text-sm",
      aria: { label: "Reservation information" },
      data: { controller: "analytics", testid: "details" }
    )

    expect(page).to have_css("#booking-details.mt-4[aria-label='Reservation information'][data-testid='details']")
    expect(page.find("#booking-details")["data-controller"]).to eq("analytics panels-ui--collapsible")
    expect(page).to have_css("#booking-details-trigger.px-3")
    expect(page).to have_css("#booking-details-content.text-sm", visible: :all)
  end

  it "optionally wraps its trigger in a heading and names a panel region" do
    render_collapsible(heading_level: 3, region: true)

    expect(page).to have_css("h3.panel-collapsible__heading > #booking-details-trigger")
    expect(page).to have_css("#booking-details-content[role='region'][aria-labelledby='booking-details-trigger']", visible: :all)
  end

  it "requires both composition slots" do
    expect do
      render_inline(described_class.new(id: "incomplete")) { |collapsible| collapsible.with_trigger { "Trigger" } }
    end.to raise_error(ArgumentError, "Collapsible requires a body slot")
  end
end
