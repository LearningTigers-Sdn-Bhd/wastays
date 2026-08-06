# frozen_string_literal: true

module HotelPortal
  # Compatibility redirects for the former operational Night Audit pages.
  # Running an audit now happens in NightAuditRunsController and historical
  # evidence belongs to HotelPortal::Reports::NightAuditsController.
  class NightAuditsController < BaseController
    before_action :authorize_night_audit_report_access!
    before_action -> { require_feature!("no_show_auto_handling") }

    def index
      redirect_to hotel_reports_night_audits_path(current_hotel), status: :moved_permanently
    end

    def show
      night_audit = current_hotel.night_audits.where.not(status: "preparing").find(params[:id])
      redirect_to hotel_reports_night_audit_path(
        current_hotel,
        night_audit,
        format: request.format.symbol == :html ? nil : request.format.symbol,
        **request.query_parameters
      ), status: :moved_permanently
    end

    private

    def authorize_night_audit_report_access!
      allowed = current_user.has_permission?("view_reports", hotel: current_hotel) ||
        current_user.has_permission?("manage_night_audit", hotel: current_hotel)
      raise Pundit::NotAuthorizedError unless allowed
    end
  end
end
