# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Button, type: :component do
  def render_button(**opts, &block)
    render_inline(described_class.new(**opts), &block)
  end

  it "renders a button with safe defaults" do
    render_button { "Save" }

    expect(page).to have_button("Save")
    button = page.find("button")
    expect(button[:type]).to eq("button")
    expect(button[:class]).to include("panel-button")
    expect(button["data-variant"]).to eq("primary")
    expect(button["data-size"]).to eq("md")
  end

  it "renders a link when href is provided" do
    render_button(href: "/bookings", variant: :secondary) { "Bookings" }

    link = page.find("a", text: "Bookings")
    expect(link[:href]).to eq("/bookings")
    expect(link["data-variant"]).to eq("secondary")
    expect(page).to have_no_css("button")
  end

  it "passes through arbitrary html, data, aria, and command attributes" do
    render_button(
      id: "open-invite",
      command: "show-modal",
      commandfor: "invite-dialog",
      onclick: "trackClick()",
      data: { turbo_frame: "modal" },
      aria: { controls: "invite-dialog" },
      class: "w-full rounded-2xl"
    ) { "Invite" }

    button = page.find("button#open-invite")
    expect(button[:command]).to eq("show-modal")
    expect(button[:commandfor]).to eq("invite-dialog")
    expect(button[:onclick]).to eq("trackClick()")
    expect(button["data-turbo-frame"]).to eq("modal")
    expect(button["aria-controls"]).to eq("invite-dialog")
    expect(button[:class]).to include("panel-button")
    expect(button[:class]).to include("w-full")
    expect(button[:class]).to include("rounded-2xl")
  end

  it "applies known variants and sizes while falling back for unknown values" do
    render_button(variant: :destructive, size: :icon, aria_label: "Delete") { "Delete" }
    expect(page.find("button")["data-variant"]).to eq("destructive")
    expect(page.find("button")["data-size"]).to eq("icon")
    expect(page.find("button")["data-icon-only"]).to eq("true")

    render_button(variant: :bogus, size: :huge) { "Fallback" }
    expect(page.find("button", text: "Fallback")["data-variant"]).to eq("primary")
    expect(page.find("button", text: "Fallback")["data-size"]).to eq("md")
  end

  it "supports the complete Nova size scale" do
    %i[xs sm md lg].each do |size|
      render_button(size: size) { size.to_s }
      expect(page.find("button", text: size.to_s)["data-size"]).to eq(size.to_s)
    end

    %i[icon_xs icon_sm icon icon_lg].each do |size|
      render_button(size: size, aria_label: size.to_s) { '<svg aria-hidden="true"></svg>'.html_safe }
      button = page.find("button[aria-label='#{size}']")
      expect(button["data-size"]).to eq(size.to_s)
      expect(button["data-icon-only"]).to eq("true")
    end
  end

  it "uses a real disabled attribute for button elements" do
    render_button(disabled: true) { "Disabled" }

    button = page.find("button[disabled]", text: "Disabled")
    expect(button[:disabled]).to eq("disabled")
    expect(button["aria-disabled"]).to be_nil
  end

  it "uses aria-disabled and removes href/focus for disabled links" do
    render_button(href: "/danger", disabled: true) { "Disabled link" }

    link = page.find("a", text: "Disabled link")
    expect(link[:href]).to be_nil
    expect(link["aria-disabled"]).to eq("true")
    expect(link[:tabindex]).to eq("-1")
  end

  it "supports an accessible name for icon-only buttons" do
    render_button(size: :icon, aria_label: "Open messages") do
      '<svg aria-hidden="true"></svg>'.html_safe
    end

    button = page.find("button[aria-label='Open messages']")
    expect(button["data-icon-only"]).to eq("true")
  end

  it "rejects icon-only buttons without an accessible name" do
    expect { render_button(size: :icon) { '<svg aria-hidden="true"></svg>'.html_safe } }.to raise_error(
      ArgumentError,
      "Icon-only buttons require an aria_label or aria: { label: ... }"
    )
  end
end
