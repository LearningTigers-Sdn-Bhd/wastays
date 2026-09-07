# frozen_string_literal: true

module HotelPortal
  module Reports
    class NightAuditsController < HotelPortal::ReportsBaseController
      before_action :authorize_night_audit_report_access!
      before_action :set_night_audit, only: :show

      def index
        report_scope = current_hotel.night_audits.where.not(status: "preparing")
        @pagy, @night_audits = pagy(
          :offset,
          report_scope.includes(:performed_by_user, :financial_summary).recent_first,
          limit: 25
        )
        @presenter = HotelPortal::Reports::NightAudits::IndexPresenter.new(
          night_audits: @night_audits,
          status_counts: report_scope.group(:status).count,
          currency: current_hotel.default_currency
        )
      end

      def show
        respond_to do |format|
          format.html do
            @presenter = HotelPortal::Reports::NightAudits::ShowPresenter.new(
              night_audit: @night_audit,
              adjustments: adjustments_for_business_date,
              currency: current_hotel.default_currency
            )
          end
          format.pdf do
            send_data ::NightAudits::AuditPacketPdfExport.new(
              night_audit: @night_audit, prepared_by: current_user.name
            ).generate,
              filename: audit_packet_filename,
              type: "application/pdf",
              disposition: "inline"
          end
        end
      end

      private

      def authorize_night_audit_report_access!
        allowed = current_user.has_permission?("view_reports", hotel: current_hotel) ||
          current_user.has_permission?("manage_night_audit", hotel: current_hotel)
        raise Pundit::NotAuthorizedError unless allowed
      end

      def set_night_audit
        @night_audit = current_hotel.night_audits
          .where.not(status: "preparing")
          .includes(:performed_by_user, :financial_summary)
          .find(params[:id])
      end

      def audit_packet_filename
        hotel_name = current_hotel.name.gsub(/\s+/, "_")
        "Audit_Packet_#{hotel_name}_#{@night_audit.business_date}.pdf"
      end

      def adjustments_for_business_date
        FolioTransaction
          .joins(booking_folio: :booking)
          .where(bookings: { hotel_id: current_hotel.id })
          .where(category: %w[adjustment discount correction write_off])
          .where(created_at: current_hotel.business_day_window_for(@night_audit.business_date))
          .includes(:user, booking_folio: :booking)
          .order(:created_at)
      end
    end
  end
end
