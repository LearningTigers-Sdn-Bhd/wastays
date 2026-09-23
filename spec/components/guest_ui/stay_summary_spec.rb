# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::StaySummary, type: :component do
  let(:badge) { GuestUI::StatusBadge.new(label: "Checked in", tone: :success) }

  def summary(**options)
    described_class.new(eyebrow: "Your Stay", property: "Aurora Crown", dates: "22 Sep – 26 Sep 2026",
                        badge:, location: "Langkawi, Malaysia", detail: "4 nights · 2 adults",
                        reference: "AUR-RES-2026-00042", code: "WS-8KD2QX", **options)
  end

  it "shows the stay, its status, both numbers, and the actions" do
    render_inline(summary(heading_level: 1)) do |component|
      component.with_actions { "Open concierge" }
    end

    expect(page).to have_css(".guest-stay-summary h1", text: "Aurora Crown")
    expect(page).to have_css(".guest-stay-summary__eyebrow", text: "Your Stay")
    expect(page).to have_css(".guest-status-badge", text: "Checked in")
    expect(page).to have_text("Langkawi, Malaysia")
    expect(page).to have_css(".guest-stay-summary__refs dd", text: "AUR-RES-2026-00042")
    expect(page).to have_css(".guest-stay-summary__refs dd", text: "WS-8KD2QX")
    expect(page).to have_css(".guest-stay-summary__actions", text: "Open concierge")
  end

  it "drops a missing number rather than printing an empty label" do
    render_inline(summary(reference: nil))

    expect(page).to have_css(".guest-stay-summary__refs dd", count: 1)
    expect(page).to have_no_css(".guest-stay-summary__actions")
  end
end
