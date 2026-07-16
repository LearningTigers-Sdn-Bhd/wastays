# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::AvatarGroup, type: :component do
  it "renders avatars and an accessible overflow count at the group size" do
    render_inline(described_class.new(aria_label: "Assigned staff", size: :sm)) do |group|
      group.with_avatar(name: "Aisha Rahman")
      group.with_avatar(name: "Daniel Wong", size: :lg)
      group.with_count(count: 4)
    end

    expect(page).to have_css(
      ".panel-avatar-group[role='group'][aria-label='Assigned staff'][data-size='sm']" \
      "[data-variant='compact'][data-slot='avatar-group']"
    )
    expect(page).to have_css(".panel-avatar-group .panel-avatar[data-size='sm']", count: 2)
    expect(page).to have_css(
      ".panel-avatar-group__count[data-size='sm'][aria-label='4 more']",
      text: "+4"
    )
  end

  it "supports the loose variant, a custom count label, classes, and attributes" do
    render_inline(described_class.new(
      aria_label: "Reviewers", size: :huge, variant: :loose,
      class: "mt-2", id: "reviewers", data: { testid: "reviewers" }
    )) do |group|
      group.with_avatar(name: "Nur Imani")
      group.with_count(count: 2, label: "Two additional reviewers")
    end

    expect(page).to have_css(
      "#reviewers.panel-avatar-group.mt-2[data-testid='reviewers'][data-size='default'][data-variant='loose']"
    )
    expect(page).to have_css(".panel-avatar-group__count[aria-label='Two additional reviewers']", text: "+2")
  end

  it "falls back to compact for an unknown variant" do
    render_inline(described_class.new(aria_label: "Team", variant: :stacked)) do |group|
      group.with_avatar(name: "Aisha Rahman")
    end

    expect(page).to have_css(".panel-avatar-group[data-variant='compact']")
  end

  it "allows an overflow count without visible avatars" do
    render_inline(described_class.new(aria_label: "Hidden team")) do |group|
      group.with_count(count: 8)
    end

    expect(page).to have_css(".panel-avatar-group__count", text: "+8")
  end

  it "rejects missing labels, empty groups, and non-positive counts" do
    expect do
      render_inline(described_class.new(aria_label: nil)) { |group| group.with_avatar(name: "Guest") }
    end.to raise_error(ArgumentError, "Avatar group aria_label is required")

    expect { render_inline(described_class.new(aria_label: "Empty")) }
      .to raise_error(ArgumentError, "Avatar group requires an avatar or count")

    expect do
      render_inline(described_class.new(aria_label: "Team")) { |group| group.with_count(count: 0) }
    end.to raise_error(ArgumentError, "Avatar group count must be positive")
  end
end
