# frozen_string_literal: true

module HotelPortal::OnboardingHelper
  STATE_LABELS = {
    "not_started" => "Not started",
    "in_progress" => "In progress",
    "complete" => "Complete",
    "skipped" => "Skipped",
    "needs_attention" => "Needs attention"
  }.freeze

  STATE_VARIANTS = {
    "not_started" => :neutral,
    "in_progress" => :info,
    "complete" => :success,
    "skipped" => :warning,
    "needs_attention" => :destructive
  }.freeze

  def onboarding_section_path_for(entry)
    hotel_onboarding_section_path(current_hotel, section_key: entry.definition.route_name)
  end

  def onboarding_state_label(state)
    STATE_LABELS.fetch(state)
  end

  def onboarding_state_variant(state)
    STATE_VARIANTS.fetch(state)
  end
end
