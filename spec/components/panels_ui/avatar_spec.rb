# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Avatar, type: :component do
  it "renders initials and accessible defaults" do
    render_inline(described_class.new(name: "Aisha Rahman"))

    expect(page).to have_css(
      "span.panel-avatar[role='img'][aria-label='Aisha Rahman'][data-slot='avatar'][data-size='default']"
    )
    expect(page).to have_css(".panel-avatar__fallback[data-slot='avatar-fallback']", text: "AR")
    expect(page).to have_no_css("img")
  end

  it "builds one or two initials from Unicode name tokens" do
    render_inline(described_class.new(name: "Élodie"))
    expect(page).to have_css(".panel-avatar__fallback", text: "É")

    render_inline(described_class.new(name: "李 小龍"))
    expect(page).to have_css(".panel-avatar__fallback", text: "李小")
  end

  it "supports every size and falls back from an unknown size" do
    described_class::SIZES.each do |size|
      render_inline(described_class.new(name: size.to_s, size: size))
      expect(page).to have_css(".panel-avatar[data-size='#{size}']")
    end

    render_inline(described_class.new(name: "Unknown", size: :huge))
    expect(page).to have_css(".panel-avatar[data-size='default']")
  end

  it "prefers an icon over an explicit fallback and generated initials" do
    render_inline(described_class.new(name: "Corporate Account", fallback: "CA", icon: "building-2"))

    expect(page).to have_css(".panel-avatar__fallback .panel-avatar__fallback-icon")
    expect(page).to have_no_css(".panel-avatar__fallback", text: "CA")
  end

  it "renders an image over its fallback with failure-controller hooks" do
    render_inline(described_class.new(name: "Aisha Rahman", src: "/aisha.png", fallback: "Guest"))

    expect(page).to have_css(".panel-avatar[data-controller='panels-ui--avatar']")
    expect(page).to have_css(
      "img.panel-avatar__image[src='/aisha.png'][alt=''][data-panels-ui--avatar-target='image'][data-slot='avatar-image']" \
      "[data-action='error->panels-ui--avatar#hideFailedImage']"
    )
    expect(page).to have_css(".panel-avatar__fallback", text: "Guest")
  end

  it "supports semantic badges, icon content, and a combined accessible label" do
    described_class::Badge::VARIANTS.each do |variant|
      render_inline(described_class.new(name: "Guest")) do |avatar|
        avatar.with_badge(label: variant.to_s.humanize, variant: variant) do
          '<svg aria-hidden="true"></svg>'.html_safe
        end
      end

      expect(page).to have_css(
        ".panel-avatar[aria-label='Guest, #{variant.to_s.humanize}'] .panel-avatar__badge[data-variant='#{variant}'] svg"
      )
    end
  end

  it "renders a dot badge without block content" do
    render_inline(described_class.new(name: "Guest")) do |avatar|
      avatar.with_badge(label: "Online", variant: :success)
    end

    expect(page).to have_css(".panel-avatar__badge:empty[data-variant='success']")
  end

  it "merges caller classes and attributes while respecting an aria override" do
    render_inline(described_class.new(
      name: "Guest", class: "ml-2", id: "guest-avatar",
      data: { testid: "guest" }, aria: { label: "Account owner" }
    ))

    expect(page).to have_css(
      "#guest-avatar.panel-avatar.ml-2[data-testid='guest'][aria-label='Account owner']"
    )
  end

  it "rejects a missing name and badge label" do
    expect { render_inline(described_class.new(name: nil)) }.to raise_error(ArgumentError, "Avatar name is required")

    expect do
      render_inline(described_class.new(name: "Guest")) { |avatar| avatar.with_badge(label: "") }
    end.to raise_error(ArgumentError, "Avatar badge label is required")
  end
end
