# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Setup::Stepper, type: :component do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "setup") }

  before { Onboarding::InitializeProgress.new(hotel: hotel).call }

  def render_stepper(section_key)
    navigation = Onboarding::NavigationState.new(hotel: hotel).call
    render_inline(described_class.new(presenter: HotelPortal::OnboardingPresenter.new(
      hotel: hotel,
      navigation: navigation,
      current_entry: navigation.fetch(section_key)
    )))
  end

  it "renders the step row even when the phase has a single step" do
    render_stepper("property_profile")

    # Property is a one-step phase. The row still renders so moving between
    # phases never shifts the page vertically.
    expect(page).to have_css("nav[aria-label='Property steps'] .tabs-tab", count: 1)
    expect(page).to have_css("nav[aria-label='Property steps'] [aria-current='page']", text: "1. Property profile")
  end

  it "renders a locked step as an inert, labelled tab" do
    %w[property_profile roles_permissions staff_setup].each do |key|
      hotel.onboarding_sections.find_by!(section_key: key).update!(state: "complete")
    end

    render_stepper("taxes_fees")

    expect(page).to have_css("nav[aria-label='Finance steps'] a[aria-current='page']", text: "1. Taxes and fees")
    expect(page).to have_css(
      "nav[aria-label='Finance steps'] span[aria-disabled='true']",
      text: "2. Room revenue · Locked"
    )
  end
end
