# frozen_string_literal: true

module Admin
  module Hotels
    class OnboardingOverviewPresenter
      Metric = Data.define(:label, :value, :detail, :detail_variant)
      DetailRow = Data.define(:label, :value)
      RoomRow = Data.define(:name, :quantity)

      INVITATION_DELIVERY_TYPES = %w[staff_invitation corporate_invitation].freeze

      def initialize(submission:)
        @submission = submission
        @snapshot = submission.snapshot.to_h.deep_stringify_keys
        @snapshot_summary = Onboarding::SnapshotSummaryPresenter.new(snapshot: @snapshot)
      end

      delegate :groups, to: :snapshot_summary

      def metrics
        [ required_setup_metric, optional_decisions_metric, rooms_metric, rate_coverage_metric ]
      end

      def property_rows
        property = snapshot.fetch("property", {})
        location = [ property["city"], property["country"] ].compact_blank.join(", ")

        [
          DetailRow.new(label: "Name", value: supplied_value(property["name"])),
          DetailRow.new(label: "Address", value: supplied_value(property["address"])),
          DetailRow.new(label: "Location", value: supplied_value(location)),
          DetailRow.new(label: "Currency", value: supplied_value(property["default_currency"])),
          DetailRow.new(label: "Sell mode", value: supplied_value(property["sell_mode"]&.humanize)),
          DetailRow.new(label: "Photos", value: supplied_value(property["photo_count"]))
        ]
      end

      def room_rows
        rooms.map do |room|
          RoomRow.new(name: supplied_value(room["name"], fallback: "Unnamed room type"),
                      quantity: supplied_value(room["quantity"]))
        end
      end

      def commercial_rows
        commercial = snapshot.fetch("commercial", {})
        {
          "Extra charges" => commercial["extra_charges"],
          "Discounts" => commercial["discounts"],
          "Payment methods" => commercial["payment_methods"],
          "Corporate accounts" => commercial["corporate_accounts"]
        }.map do |label, rows|
          DetailRow.new(label:, value: Array(rows).size.to_s)
        end
      end

      def handover_rows
        rows = [ DetailRow.new(label: "Invitation delivery", value: invitation_delivery_summary) ]
        channels = Array(snapshot["ota_handover"])
        if channels.empty?
          rows << DetailRow.new(label: "Channel handover", value: "No channels submitted")
        else
          channels.each do |channel|
            status = channel["credentials_supplied"] == false ? "Credentials not supplied" : "Credentials supplied"
            rows << DetailRow.new(label: supplied_value(channel["channel_name"], fallback: "Unnamed channel"), value: status)
          end
        end
        rows
      end

      private

      attr_reader :submission, :snapshot, :snapshot_summary

      def required_setup_metric
        definitions = setup_definitions.select(&:required)
        complete = definitions.count { |definition| state_for(definition) == "complete" }
        remaining = definitions.size - complete
        Metric.new(
          label: "Required setup",
          value: "#{complete} of #{definitions.size}",
          detail: remaining.zero? ? "Complete" : "#{remaining} remaining",
          detail_variant: remaining.zero? ? :success : :warning
        )
      end

      def optional_decisions_metric
        definitions = setup_definitions.reject(&:required)
        resolved = definitions.count { |definition| state_for(definition).in?(%w[complete skipped]) }
        deferred = definitions.count { |definition| state_for(definition) == "skipped" }
        Metric.new(
          label: "Optional decisions",
          value: "#{resolved} of #{definitions.size}",
          detail: "#{deferred} deferred",
          detail_variant: resolved == definitions.size ? :success : :warning
        )
      end

      def rooms_metric
        total = rooms.sum { |room| room["quantity"].to_i }
        Metric.new(
          label: "Rooms",
          value: total.to_s,
          detail: "#{rooms.size} #{'room type'.pluralize(rooms.size)}",
          detail_variant: :neutral
        )
      end

      def rate_coverage_metric
        coverage = snapshot.dig("rates", "coverage") || {}
        Metric.new(
          label: "Rate coverage",
          value: percentage(coverage["configured_percentage"]),
          detail: coverage_date(coverage["end_date"]),
          detail_variant: coverage["complete"] == true ? :success : :warning
        )
      end

      def setup_definitions
        Onboarding::SectionCatalog.all.reject { |definition| definition.key == "review" }
      end

      def state_for(definition)
        snapshot.dig("sections", definition.key, "state")
      end

      def rooms = Array(snapshot["rooms"])

      def percentage(value)
        return "Not supplied" if value.blank?

        number = BigDecimal(value.to_s).to_s("F").sub(/\.0+\z/, "")
        "#{number}%"
      rescue ArgumentError
        "Not supplied"
      end

      def coverage_date(value)
        return "No coverage date" if value.blank?

        "Through #{I18n.l(Date.iso8601(value), format: '%d %b %Y')}"
      rescue Date::Error
        "No coverage date"
      end

      def invitation_delivery_summary
        deliveries = Array(submission.deliveries).select do |delivery|
          delivery.delivery_type.in?(INVITATION_DELIVERY_TYPES)
        end
        return "No invitations created" if deliveries.empty?

        counts = deliveries.group_by(&:status).transform_values(&:size)
        pending = counts.fetch("pending", 0) + counts.fetch("processing", 0)
        "#{counts.fetch('sent', 0)} sent · #{counts.fetch('held', 0)} held · #{pending} pending · #{counts.fetch('failed', 0)} failed"
      end

      def supplied_value(value, fallback: "Not supplied")
        value.present? || value == 0 ? value.to_s : fallback
      end
    end
  end
end
