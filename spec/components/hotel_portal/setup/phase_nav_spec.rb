# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Setup::PhaseNav, type: :component do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "setup") }

  before { Onboarding::InitializeProgress.new(hotel: hotel).call }

  def complete!(*section_keys)
    section_keys.each do |key|
      hotel.onboarding_sections.find_by!(section_key: key).update!(state: "complete")
    end
  end

  def render_phase_nav(section_key)
    navigation = Onboarding::NavigationState.new(hotel: hotel).call
    render_inline(described_class.new(presenter: HotelPortal::OnboardingPresenter.new(
      hotel: hotel,
      navigation: navigation,
      current_entry: navigation.fetch(section_key)
    )))
  end

  it "renders one continuous run of chevron segments" do
    render_phase_nav("property_profile")

    nav = page.find("nav[aria-label='Onboarding progress']")

    expect(nav).to have_css("ol.panel-step-bar > li.panel-step-bar__item", count: 6)
    expect(nav).to have_css(".panel-step-bar__step", count: 6)
    expect(nav).to have_no_css("[class*='rounded-md border'], [class*='bg-card']")
  end

  it "fills the segments by state, with the current phase taking the solid fill" do
    complete!("property_profile", "property_photos", "team_setup")
    render_phase_nav("taxes_fees")

    nav = page.find("nav[aria-label='Onboarding progress']")

    expect(nav.find("li", text: "Property")).to have_css("[data-state='complete']")
    expect(nav.find("li", text: "Finance")).to have_css("[data-state='current'][aria-current='step']")
    expect(nav.find("li", text: "Commercial")).to have_css("[data-state='locked']")
  end

  it "marks the current phase without relying on colour" do
    render_phase_nav("property_profile")

    current = page.find("nav[aria-label='Onboarding progress'] [aria-current='step']")

    expect(current).to have_css("[data-marker='number']", text: "1")
    expect(current).to have_css("span.sr-only", text: "Not started", visible: :all)
  end

  it "swaps the marker glyph for completed, locked, and attention states" do
    complete!("property_profile", "property_photos")
    hotel.onboarding_sections.find_by!(section_key: "team_setup").update!(state: "needs_attention")

    render_phase_nav("team_setup")
    nav = page.find("nav[aria-label='Onboarding progress']")

    expect(nav.find("li", text: "Property")).to have_css("[data-marker='check']")
    expect(nav.find("li", text: "Team")).to have_css("[data-marker='warning']")
    expect(nav.find("li", text: "Commercial")).to have_css("[data-marker='lock']")
  end

  it "keeps a locked phase visible but not navigable" do
    render_phase_nav("property_profile")

    commercial = page.find("nav[aria-label='Onboarding progress'] li", text: "Commercial")

    expect(commercial).to have_css("[aria-disabled='true']")
    expect(commercial).to have_no_css("a")
    expect(commercial).to have_css("span.sr-only", text: "Not started", visible: :all)
  end

  it "offers the same journey through a compact control on small screens" do
    render_phase_nav("property_profile")

    # The list is collapsed until the summary is opened, so assert against the
    # full DOM rather than what is currently painted.
    expect(page).to have_css("details.md\\:hidden summary", text: "Property · Phase 1 of 6")
    expect(page).to have_css("details.md\\:hidden li", text: "Rooms & rates", visible: :all)
    expect(page).to have_css("details.md\\:hidden li [aria-disabled='true']", text: "Locked", visible: :all)
  end
end
