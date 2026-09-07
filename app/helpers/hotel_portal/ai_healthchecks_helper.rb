# frozen_string_literal: true

module HotelPortal
  # Badge colours for the AI Concierge healthcheck table. A diagnostic carries
  # three separate signals, so each one gets its own scale.
  module AiHealthchecksHelper
    # How far the review has got. Open needs attention, resolved does not.
    STATUS_VARIANTS = {
      "open" => :warning,
      "reviewed" => :info,
      "resolved" => :success,
      "dismissed" => :neutral
    }.freeze

    # How the concierge answered. Unavailable means the guest got nothing.
    ANSWER_MODE_VARIANTS = {
      "unavailable" => :destructive,
      "fallback" => :warning,
      "weak_match" => :warning,
      "deterministic" => :success,
      "structured" => :success,
      "synthesized" => :info
    }.freeze

    def healthcheck_status_badge(status)
      value = status.to_s
      render PanelsUI::Badge.new(
        label: value.presence&.humanize || "Unknown",
        variant: STATUS_VARIANTS.fetch(value, :neutral),
        size: :xs,
        shape: :rounded
      )
    end

    def healthcheck_answer_mode_badge(answer_mode)
      value = answer_mode.to_s
      render PanelsUI::Badge.new(
        label: value.presence&.humanize || "Unknown",
        variant: ANSWER_MODE_VARIANTS.fetch(value, :neutral),
        size: :xs,
        shape: :rounded
      )
    end

    def healthcheck_category_badge(category)
      value = category.to_s
      render PanelsUI::Badge.new(
        label: value.presence&.humanize || "Uncategorized",
        variant: value.present? ? :accent : :outline,
        size: :xs,
        shape: :rounded
      )
    end

    def healthcheck_status_options
      HotelKnowledgeDiagnostic::STATUSES.map { |status| [ status.humanize, status ] }
    end

    def healthcheck_answer_mode_options
      ANSWER_MODE_VARIANTS.keys.map { |mode| [ mode.humanize, mode ] }
    end

    def healthcheck_category_options
      HotelKnowledgeDiagnostic::SUGGESTED_CATEGORIES.map { |category| [ category.humanize, category ] }
    end
  end
end
