# frozen_string_literal: true

module HotelPortal
  class KnowledgeDiagnosticsController < HotelPortal::BaseController
    before_action :set_hotel
    before_action :authorize_hotel
    before_action :set_diagnostic, only: :update

    def index
      @status = permitted_filter(:status, HotelKnowledgeDiagnostic::STATUSES)
      @answer_mode = params[:answer_mode].to_s.presence
      @suggested_category = permitted_filter(:suggested_category, HotelKnowledgeDiagnostic::SUGGESTED_CATEGORIES)
      @start_date = parse_date(params[:start_date])
      @end_date = parse_date(params[:end_date])

      @diagnostics = filtered_diagnostics
      @summary_counts = summary_counts
    end

    def update
      status = permitted_diagnostic_status
      if status.present? && @diagnostic.update(diagnostic_status: status)
        redirect_back fallback_location: hotel_knowledge_diagnostics_path(@hotel), notice: "Diagnostic marked as #{status.humanize.downcase}."
      else
        redirect_back fallback_location: hotel_knowledge_diagnostics_path(@hotel), alert: "Unable to update diagnostic."
      end
    end

    private

    def set_hotel
      @hotel = current_hotel
    end

    def authorize_hotel
      authorize @hotel, :update?, policy_class: HotelPolicy
    end

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

    def permitted_filter(key, allowed)
      value = params[key].to_s
      allowed.include?(value) ? value : nil
    end

    def permitted_diagnostic_status
      value = params.dig(:hotel_knowledge_diagnostic, :diagnostic_status).presence || params[:diagnostic_status]
      HotelKnowledgeDiagnostic::STATUSES.include?(value.to_s) ? value.to_s : nil
    end

    def parse_date(value)
      Date.iso8601(value.to_s) if value.present?
    rescue Date::Error
      nil
    end
  end
end
