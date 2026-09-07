# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # The Healthcheck sub-tab of AI Concierge. It lists the guest questions that
    # the concierge answered badly, or could not answer at all.
    class AiHealthchecksController < HotelPortal::GuestContent::BaseController
      include ReportDateFiltering
      include SheetActionCompletion

      DATE_PARAM_KEYS = %i[date_preset date_range start_date end_date].freeze

      before_action -> { require_feature!("ai_concierge_page") }
      before_action :set_diagnostic, only: %i[show update]

      def index
        @status = permitted_filter(:status, HotelKnowledgeDiagnostic::STATUSES)
        @answer_mode = params[:answer_mode].to_s.presence
        @suggested_category = permitted_filter(:suggested_category, HotelKnowledgeDiagnostic::SUGGESTED_CATEGORIES)
        @start_date, @end_date = parse_healthcheck_date_range

        @diagnostics = filtered_diagnostics
        @summary_counts = summary_counts
      end

      def show
        render layout: false
      end

      def update
        status = permitted_diagnostic_status

        if status.present? && @diagnostic.update(diagnostic_status: status)
          finish_sheet("Diagnostic marked as #{status.humanize.downcase}.")
        else
          # Only a tampered request gets here, because the sheet offers the four
          # valid statuses and nothing else. Keep the sheet open and say so.
          @error = "Choose one of the four review statuses."
          render :show, layout: false, status: :unprocessable_content
        end
      end

      private

      def set_diagnostic
        @diagnostic = @hotel.knowledge_diagnostics.find(params[:id])
      end

      def filtered_diagnostics
        @hotel.knowledge_diagnostics
          .for_status(@status)
          .for_answer_mode(@answer_mode)
          .for_suggested_category(@suggested_category)
          .created_from(@start_date)
          .created_until(@end_date)
          .recent_first
      end

      def summary_counts
        scope = @hotel.knowledge_diagnostics
        {
          open: scope.where(diagnostic_status: "open").count,
          weak: scope.unavailable_or_weak.count,
          reviewed: scope.where(diagnostic_status: "reviewed").count,
          resolved: scope.where(diagnostic_status: "resolved").count
        }
      end

      # The reports time filter defaults to today. A healthcheck list that starts
      # empty every morning helps nobody, so this page starts on all time.
      def parse_healthcheck_date_range
        parser = HotelPortal::Reports::DateRangeParser.new(healthcheck_date_params, current_hotel)
        range = parser.parse_range
        @date_preset = parser.date_preset
        range
      end

      def healthcheck_date_params
        return params if DATE_PARAM_KEYS.any? { |key| params[key].present? }

        params.merge(date_preset: "all_time")
      end

      def permitted_filter(key, allowed)
        value = params[key].to_s
        allowed.include?(value) ? value : nil
      end

      def permitted_diagnostic_status
        value = params.dig(:hotel_knowledge_diagnostic, :diagnostic_status).presence || params[:diagnostic_status]
        HotelKnowledgeDiagnostic::STATUSES.include?(value.to_s) ? value.to_s : nil
      end

      def finish_sheet(notice)
        complete_sheet_action(
          destination: hotel_ai_healthchecks_path(@hotel),
          notice: notice,
          frame: sheet_frame
        )
      end

      def sheet_frame
        turbo_frame_request_id.presence || "settings_action_sheet"
      end
    end
  end
end
