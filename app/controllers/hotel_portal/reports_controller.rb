# frozen_string_literal: true

require "csv"

module HotelPortal
  class ReportsController < HotelPortal::BaseController
    include FinancialFiltering

    PAYOUT_TABS = %w[upcoming paid].freeze
    GUEST_REPORT_TABS = %w[arrivals in_house departures checkout registration_cards].freeze
    EXTRA_CHARGE_REPORT_TABS = %w[fb non_fb].freeze

    before_action :authorize_view_reports!, only: %i[index breakdown daily_occupancy daily_revenue managers_flash outstanding_balance deposit_liability arrivals_departures folio_ledger journal_batches sst refund_report extra_charge non_national tourism_tax guest_registration_cards]
    before_action :authorize_view_payouts!, only: %i[payouts]
    before_action -> { require_feature!("daily_occupancy_revenue") }, only: %i[daily_occupancy]
    before_action -> { require_feature!("arrivals_departures_list") }, only: %i[arrivals_departures]
    before_action -> { require_feature!("outstanding_balance_noshow") }, only: %i[outstanding_balance]
    before_action -> { require_feature!("housekeeper_productivity") }, only: %i[managers_flash]
    before_action -> { require_feature!("booking_source_analysis") }, only: %i[breakdown]
    before_action -> { require_feature!("revenue_allocation_per_night") }, only: %i[daily_revenue]
    before_action -> { require_feature!("excel_pdf_export") }, if: -> { %i[csv xls pdf].include?(request.format.symbol) }

    def index
      # Note: FinancialFiltering sets @start_date and @end_date
      hotel_bookings = current_hotel.bookings.revenue_generating

      summary = Booking.analytics_summary(@start_date, @end_date, query: params[:q], base_scope: hotel_bookings)
      @total_gross = summary[:total_revenue]
      @total_margin = summary[:total_margin]
      @total_net = summary[:total_net]
      @booking_count = summary[:booking_count]

      @bookings = hotel_bookings.created_between(@start_date, @end_date)
                               .search(params[:q])
                               .includes(booking_rooms: :room_type)
      @base_bookings = @bookings
      @daily_data = Booking.daily_revenue_data(@bookings).to_a
      @paginated_daily_data = Kaminari.paginate_array(@daily_data).page(params[:page]).per(25)

      respond_to do |format|
        format.html
        format.csv do
          csv = financial_performance_export_service.generate_csv
          send_data csv,
            filename: "financial-performance-#{@start_date}-#{@end_date}.csv",
            type: "text/csv"
        end
        format.any(:xls) do
          workbook = financial_performance_export_service.generate_xls
          send_data workbook,
            filename: "financial-performance-#{@start_date}-#{@end_date}.xls",
            type: "application/vnd.ms-excel",
            disposition: "attachment"
        end
        format.pdf do
          pdf = financial_performance_export_service.generate_pdf
          send_data pdf,
            filename: "financial-performance-#{@start_date}-#{@end_date}.pdf",
            type: "application/pdf",
            disposition: "attachment"
        end
      end
    end

    def payouts
      cutoff_date = Booking.last_friday.end_of_day
      @active_tab = PAYOUT_TABS.include?(params[:tab]) ? params[:tab] : "upcoming"
      append_breadcrumb({ label: payout_tab_label(@active_tab), tab_label: true }) if request.format.html?

      @upcoming_bookings = current_hotel.bookings.unbatched_upcoming(cutoff_date)
      @upcoming_payout_amount = current_hotel.upcoming_payout_amount(cutoff_date)

      @processing_batches = current_hotel.payout_batches.where(status: "processing")

      @paid_start_date = parse_date_param(params[:paid_start_date])
      @paid_end_date = parse_date_param(params[:paid_end_date])

      @payout_history = current_hotel.payout_batches_for_reports(
        start_date: @paid_start_date,
        end_date: @paid_end_date
      ).page(params[:page]).per(25)

      respond_to do |format|
        format.html
        format.csv do
          csv = payouts_export_service.generate_csv
          send_data csv,
            filename: "payouts-#{@active_tab}-#{Date.current}.csv",
            type: "text/csv"
        end
        format.any(:xls) do
          workbook = payouts_export_service.generate_xls
          send_data workbook,
            filename: "payouts-#{@active_tab}-#{Date.current}.xls",
            type: "application/vnd.ms-excel",
            disposition: "attachment"
        end
        format.pdf do
          pdf = payouts_export_service.generate_pdf
          send_data pdf,
            filename: "payouts-#{@active_tab}-#{Date.current}.pdf",
            type: "application/pdf",
            disposition: "attachment"
        end
      end
    end

    def breakdown
      @bookings = Booking.for_financial_breakdown(
        current_hotel,
        @start_date,
        @end_date,
        params[:q]
      )

      respond_to do |format|
        format.html do
          @paginated_bookings = @bookings.page(params[:page]).per(25)
          @grouped_bookings = @paginated_bookings.group_by { |b| b.created_at.to_date }.transform_values do |bookings|
            bookings.map { |b| HotelPortal::BookingFinancialPresenter.new(b) }
          end
        end
        format.csv do
          send_data breakdown_export_service.generate_csv, filename: "financial-breakdown-#{@start_date}-#{@end_date}.csv"
        end
        format.any(:xls) do
          workbook = breakdown_export_service.generate_xls
          send_data workbook,
            filename: "financial-breakdown-#{@start_date}-#{@end_date}.xls",
            type: "application/vnd.ms-excel",
            disposition: "attachment"
        end
        format.pdf do
          pdf = breakdown_export_service.generate_pdf
          send_data pdf,
            filename: "financial-breakdown-#{@start_date}-#{@end_date}.pdf",
            type: "application/pdf",
            disposition: "attachment"
        end
      end
    end

    def daily_occupancy
      @report_start_date, @report_end_date = parse_report_date_range
      @report = HotelPortal::Reports::DailyOccupancyReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date,
        date_preset: params[:date_preset]
      ).call

      respond_to do |format|
        format.html
        format.csv do
          csv = HotelPortal::Reports::DailyOccupancyCsvExportService.new(report: @report).generate
          send_data csv,
            filename: "daily-occupancy-#{@report.start_date}-#{@report.end_date}.csv",
            type: "text/csv"
        end
        format.any(:xls) do
          workbook = HotelPortal::Reports::DailyOccupancyExcelExportService.new(report: @report).generate
          send_data workbook,
            filename: "daily-occupancy-#{@report.start_date}-#{@report.end_date}.xls",
            type: "application/vnd.ms-excel",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::DailyOccupancyPdfExportService.new(hotel: current_hotel, report: @report).generate
          send_data pdf,
            filename: "daily-occupancy-#{@report.start_date}-#{@report.end_date}.pdf",
            type: "application/pdf",
            disposition: "attachment"
        end
      end
    end

    def daily_revenue
      @report_start_date, @report_end_date = parse_report_date_range
      @report = HotelPortal::Reports::DailyRevenueReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date,
        date_preset: params[:date_preset]
      ).call

      respond_to do |format|
        format.html
        format.csv do
          csv = HotelPortal::Reports::DailyRevenueCsvExportService.new(report: @report).generate
          send_data csv,
            filename: "daily-revenue-#{@report.start_date}-#{@report.end_date}.csv",
            type: "text/csv"
        end
        format.any(:xls) do
          workbook = HotelPortal::Reports::DailyRevenueExcelExportService.new(report: @report).generate
          send_data workbook,
            filename: "daily-revenue-#{@report.start_date}-#{@report.end_date}.xls",
            type: "application/vnd.ms-excel",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::DailyRevenuePdfExportService.new(hotel: current_hotel, report: @report).generate
          send_data pdf,
            filename: "daily-revenue-#{@report.start_date}-#{@report.end_date}.pdf",
            type: "application/pdf",
            disposition: "attachment"
        end
      end
    end

    def managers_flash
      @report_start_date, @report_end_date = parse_report_date_range
      @report = HotelPortal::Reports::ManagersFlashReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date,
        date_preset: params[:date_preset]
      ).call

      respond_to do |format|
        format.html
        format.csv do
          csv = HotelPortal::Reports::ManagersFlashCsvExportService.new(report: @report).generate
          send_data csv,
            filename: "managers-flash-#{@report.start_date}-#{@report.end_date}.csv",
            type: "text/csv"
        end
        format.any(:xls) do
          workbook = HotelPortal::Reports::ManagersFlashExcelExportService.new(report: @report).generate
          send_data workbook,
            filename: "managers-flash-#{@report.start_date}-#{@report.end_date}.xls",
            type: "application/vnd.ms-excel",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::ManagersFlashPdfExportService.new(hotel: current_hotel, report: @report).generate
          send_data pdf,
            filename: "managers-flash-#{@report.start_date}-#{@report.end_date}.pdf",
            type: "application/pdf",
            disposition: "attachment"
        end
      end
    end

    def outstanding_balance
      @report_start_date, @report_end_date = parse_report_date_range
      @report = HotelPortal::Reports::OutstandingBalanceReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date
      ).call

      respond_to do |format|
        format.html
        format.csv do
          csv = HotelPortal::Reports::OutstandingBalanceCsvExportService.new(report: @report).generate
          send_data csv,
            filename: "outstanding-balance-#{@report.start_date}-#{@report.end_date}.csv",
            type: "text/csv"
        end
        format.any(:xls) do
          workbook = HotelPortal::Reports::OutstandingBalanceExcelExportService.new(report: @report).generate
          send_data workbook,
            filename: "outstanding-balance-#{@report.start_date}-#{@report.end_date}.xls",
            type: "application/vnd.ms-excel",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::OutstandingBalancePdfExportService.new(hotel: current_hotel, report: @report).generate
          send_data pdf,
            filename: "outstanding-balance-#{@report.start_date}-#{@report.end_date}.pdf",
            type: "application/pdf",
            disposition: "attachment"
        end
      end
    end

    def deposit_liability
      @report_as_of_date = parse_deposit_liability_date
      @report = HotelPortal::Reports::DepositLiabilityReport.new(
        hotel: current_hotel,
        as_of_date: @report_as_of_date
      ).call

      respond_to do |format|
        format.html
        format.csv do
          csv = HotelPortal::Reports::DepositLiabilityCsvExportService.new(report: @report).generate
          send_data csv,
            filename: "deposit-liability-#{@report.as_of_date}.csv",
            type: "text/csv"
        end
        format.any(:xls) do
          workbook = HotelPortal::Reports::DepositLiabilityExcelExportService.new(report: @report).generate
          send_data workbook,
            filename: "deposit-liability-#{@report.as_of_date}.xls",
            type: "application/vnd.ms-excel",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::DepositLiabilityPdfExportService.new(hotel: current_hotel, report: @report).generate
          send_data pdf,
            filename: "deposit-liability-#{@report.as_of_date}.pdf",
            type: "application/pdf",
            disposition: "attachment"
        end
      end
    end

    def arrivals_departures
      @active_guest_report_tab = GUEST_REPORT_TABS.include?(params[:tab]) ? params[:tab] : "arrivals"
      @report_start_date, @report_end_date = parse_report_date_range
      @report = HotelPortal::Reports::ArrivalsDeparturesReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date
      ).call
      load_guest_registration_cards(start_date: @report.start_date, end_date: @report.end_date)

      respond_to do |format|
        format.html
        format.csv do
          return head :not_acceptable if @active_guest_report_tab == "registration_cards"

          csv = HotelPortal::Reports::ArrivalsDeparturesCsvExportService.new(report: @report, tab: @active_guest_report_tab).generate
          send_data csv,
            filename: "guest-reports-#{@active_guest_report_tab.tr('_', '-')}-#{@report.start_date}-#{@report.end_date}.csv",
            type: "text/csv"
        end
        format.any(:xls) do
          return head :not_acceptable if @active_guest_report_tab == "registration_cards"

          workbook = HotelPortal::Reports::ArrivalsDeparturesExcelExportService.new(report: @report, tab: @active_guest_report_tab).generate
          send_data workbook,
            filename: "guest-reports-#{@active_guest_report_tab.tr('_', '-')}-#{@report.start_date}-#{@report.end_date}.xls",
            type: "application/vnd.ms-excel",
            disposition: "attachment"
        end
        format.pdf do
          return head :not_acceptable if @active_guest_report_tab == "registration_cards"

          pdf = HotelPortal::Reports::ArrivalsDeparturesPdfExportService.new(hotel: current_hotel, report: @report, tab: @active_guest_report_tab).generate
          send_data pdf,
            filename: "guest-reports-#{@active_guest_report_tab.tr('_', '-')}-#{@report.start_date}-#{@report.end_date}.pdf",
            type: "application/pdf",
            disposition: "attachment"
        end
      end
    end

    def guest_registration_cards
      load_guest_registration_cards
    end

    def load_guest_registration_cards(start_date: nil, end_date: nil)
      @status_filter = params[:status].to_s
      @grc_query = params[:q].to_s.strip
      base_scope = current_hotel.guest_registration_cards
                                .includes(:hotel, booking: :booking_rooms)
                                .joins(:booking)
      base_scope = base_scope.where(bookings: { check_in: start_date..end_date }) if start_date && end_date
      @grc_total_count = base_scope.count
      @grc_signed_count = base_scope.where(status: "signed").count
      @grc_draft_count = base_scope.where(status: "draft").count
      @grc_cards = base_scope.order("bookings.check_in DESC")
      @grc_cards = @grc_cards.where(status: @status_filter) if %w[draft signed].include?(@status_filter)
      if @grc_query.present?
        query = "%#{ActiveRecord::Base.sanitize_sql_like(@grc_query.downcase)}%"
        compact_query = "%#{ActiveRecord::Base.sanitize_sql_like(@grc_query.downcase.delete("-"))}%"
        hotel_prefix = ActiveRecord::Base.connection.quote(current_hotel.hotel_prefix.to_s.downcase)
        formatted_grc_sql = "LOWER(CONCAT(#{hotel_prefix}, '-2', LPAD(CAST(bookings.guest_registration_number AS TEXT), 7, '0')))"
        @grc_cards = @grc_cards.where(
          "LOWER(bookings.guest_name) LIKE :query OR LOWER(bookings.confirmation_token) LIKE :query OR CAST(bookings.guest_registration_number AS TEXT) LIKE :query OR #{formatted_grc_sql} LIKE :query OR REPLACE(#{formatted_grc_sql}, '-', '') LIKE :compact_query",
          compact_query: compact_query,
          query: query
        )
      end
      @grc_cards = @grc_cards.page(params[:page]).per(25)
    end

    def folio_ledger
      @start_date, @end_date = parse_date_range(params[:start_date], params[:end_date])

      # Default to the last completed night audit date if no range given
      if @start_date.nil?
        last_audit = current_hotel.night_audits.completed.order(business_date: :desc).first
        @start_date = last_audit&.business_date || Date.current - 1.day
        @end_date   = @start_date
      end

      service = folio_ledger_export_service
      @totals = service.totals

      respond_to do |format|
        format.html
        format.csv do
          send_data service.generate_csv,
            filename: "folio-ledger-#{@start_date}-#{@end_date}.csv",
            type: "text/csv"
        end
        format.any(:xls) do
          send_data service.generate_xls,
            filename: "folio-ledger-#{@start_date}-#{@end_date}.xls",
            type: "application/vnd.ms-excel",
            disposition: "attachment"
        end
      end
    end

    def journal_batches
      @report_start_date, @report_end_date = parse_report_date_range
      @batches = current_hotel.journal_batches
                              .where(business_date: @report_start_date..@report_end_date)
                              .includes(:entries)
                              .order(business_date: :desc)

      respond_to do |format|
        format.html do
          @paginated_batches = @batches.page(params[:page]).per(25)
        end
        format.csv do
          csv = HotelPortal::Reports::JournalBatchCsvExportService.new(batches: @batches).generate
          send_data csv,
            filename: "journal-batches-#{@report_start_date}-#{@report_end_date}.csv",
            type: "text/csv"
        end
      end
    end

    def sst
      @report_start_date, @report_end_date = parse_report_date_range
      @report = HotelPortal::Reports::SstReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date,
        date_preset: params[:date_preset]
      ).call

      respond_to do |format|
        format.html
        format.csv do
          csv = HotelPortal::Reports::SstCsvExportService.new(report: @report).generate
          send_data csv,
            filename: "sst-report-#{@report.start_date}-#{@report.end_date}.csv",
            type: "text/csv"
        end
        format.any(:xls) do
          workbook = HotelPortal::Reports::SstExcelExportService.new(report: @report).generate
          send_data workbook,
            filename: "sst-report-#{@report.start_date}-#{@report.end_date}.xls",
            type: "application/vnd.ms-excel",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::SstPdfExportService.new(hotel: current_hotel, report: @report).generate
          send_data pdf,
            filename: "sst-report-#{@report.start_date}-#{@report.end_date}.pdf",
            type: "application/pdf",
            disposition: "attachment"
        end
      end
    end

    def refund_report
      @report_start_date, @report_end_date = parse_report_date_range
      @report = HotelPortal::Reports::RefundReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date,
        date_preset: params[:date_preset]
      ).call

      respond_to do |format|
        format.html
        format.csv do
          csv = HotelPortal::Reports::RefundReportCsvExportService.new(report: @report).generate
          send_data csv,
            filename: "refund-report-#{@report.start_date}-#{@report.end_date}.csv",
            type: "text/csv"
        end
        format.any(:xls) do
          workbook = HotelPortal::Reports::RefundReportExcelExportService.new(report: @report).generate
          send_data workbook,
            filename: "refund-report-#{@report.start_date}-#{@report.end_date}.xls",
            type: "application/vnd.ms-excel",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::RefundReportPdfExportService.new(hotel: current_hotel, report: @report).generate
          send_data pdf,
            filename: "refund-report-#{@report.start_date}-#{@report.end_date}.pdf",
            type: "application/pdf",
            disposition: "attachment"
        end
      end
    end

    def extra_charge
      @active_extra_charge_tab = EXTRA_CHARGE_REPORT_TABS.include?(params[:tab]) ? params[:tab] : "fb"
      @report_start_date, @report_end_date = parse_report_date_range
      @report = HotelPortal::Reports::ExtraChargeReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date,
        tab: @active_extra_charge_tab
      ).call

      respond_to do |format|
        format.html
        format.csv do
          csv = HotelPortal::Reports::ExtraChargeCsvExportService.new(report: @report).generate
          send_data csv,
            filename: "extra-charge-report-#{@active_extra_charge_tab.tr('_', '-')}-#{@report.start_date}-#{@report.end_date}.csv",
            type: "text/csv"
        end
        format.any(:xls) do
          workbook = HotelPortal::Reports::ExtraChargeExcelExportService.new(report: @report).generate
          send_data workbook,
            filename: "extra-charge-report-#{@active_extra_charge_tab.tr('_', '-')}-#{@report.start_date}-#{@report.end_date}.xls",
            type: "application/vnd.ms-excel",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::ExtraChargePdfExportService.new(hotel: current_hotel, report: @report).generate
          send_data pdf,
            filename: "extra-charge-report-#{@active_extra_charge_tab.tr('_', '-')}-#{@report.start_date}-#{@report.end_date}.pdf",
            type: "application/pdf",
            disposition: "attachment"
        end
      end
    end

    def non_national
      @report_start_date, @report_end_date = parse_report_date_range
      @report = HotelPortal::Reports::NonNationalReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date
      ).call

      respond_to do |format|
        format.html
        format.csv do
          csv = HotelPortal::Reports::NonNationalCsvExportService.new(report: @report).generate
          send_data csv,
            filename: "non-national-report-#{@report.start_date}-#{@report.end_date}.csv",
            type: "text/csv"
        end
        format.any(:xls) do
          workbook = HotelPortal::Reports::NonNationalExcelExportService.new(report: @report).generate
          send_data workbook,
            filename: "non-national-report-#{@report.start_date}-#{@report.end_date}.xls",
            type: "application/vnd.ms-excel",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::NonNationalPdfExportService.new(hotel: current_hotel, report: @report).generate
          send_data pdf,
            filename: "non-national-report-#{@report.start_date}-#{@report.end_date}.pdf",
            type: "application/pdf",
            disposition: "attachment"
        end
      end
    end

    def tourism_tax
      @report_start_date, @report_end_date = parse_report_date_range
      @report = HotelPortal::Reports::TourismTaxReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date
      ).call

      respond_to do |format|
        format.html
        format.csv do
          csv = HotelPortal::Reports::TourismTaxCsvExportService.new(report: @report).generate
          send_data csv,
            filename: "tourism-tax-report-#{@report.start_date}-#{@report.end_date}.csv",
            type: "text/csv"
        end
        format.any(:xls) do
          workbook = HotelPortal::Reports::TourismTaxExcelExportService.new(report: @report).generate
          send_data workbook,
            filename: "tourism-tax-report-#{@report.start_date}-#{@report.end_date}.xls",
            type: "application/vnd.ms-excel",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::TourismTaxPdfExportService.new(hotel: current_hotel, report: @report).generate
          send_data pdf,
            filename: "tourism-tax-report-#{@report.start_date}-#{@report.end_date}.pdf",
            type: "application/pdf",
            disposition: "attachment"
        end
      end
    end

    private

    def parse_report_date_range
      # Handle date_preset parameter (e.g., "2026-05", "this_month", "custom")
      date_preset = params[:date_preset].presence
      date_preset ||= "custom" if params[:start_date].present? || params[:end_date].present?
      date_preset ||= "legacy_date" if params[:date].present?
      date_preset ||= default_report_date_preset
      @date_preset = date_preset

      if date_preset.present?
        case date_preset
        when "today"
          return [ Date.current, Date.current ]
        when "all_time"
          return [ Date.new(2024, 1, 1), Date.current ]
        when "this_year"
          return [ Date.current.beginning_of_year, Date.current.end_of_year ]
        when "last_month"
          last_month = 1.month.ago.to_date
          return [ last_month.beginning_of_month, last_month.end_of_month ]
        when "this_month"
          return [ Date.current.beginning_of_month, Date.current.end_of_month ]
        when "custom"
          start = parse_single_report_date(params[:start_date]) || Date.current.beginning_of_month
          end_date = parse_single_report_date(params[:end_date]) || Date.current.end_of_month
          end_date = start if end_date < start
          return [ start, end_date ]
        when "legacy_date"
          parsed_date = parse_single_report_date(params[:date])
          return [ parsed_date, parsed_date ] if parsed_date
        else
          # Check if it's a specific month (e.g. "2026-03")
          if date_preset =~ /\A\d{4}-\d{2}\z/
            start_date = Date.parse("#{date_preset}-01")
            return [ start_date, start_date.end_of_month ]
          end
        end
      end

      # Backward compatible: if only `date` is provided, treat it as one-day range.
      if params[:start_date].blank? && params[:end_date].blank? && params[:date].present?
        parsed_date = parse_single_report_date(params[:date])
        return [ parsed_date, parsed_date ]
      end

      start_date = parse_single_report_date(params[:start_date])
      end_date = parse_single_report_date(params[:end_date])

      start_date ||= end_date || Date.current
      end_date ||= start_date
      end_date = start_date if end_date < start_date

      [ start_date, end_date ]
    end

    def parse_single_report_date(value)
      return if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def parse_deposit_liability_date
      date_preset = params[:date_preset].presence
      date_preset ||= "custom" if params[:as_of_date].present?
      date_preset ||= "today"
      @date_preset = date_preset

      if date_preset.present?
        case date_preset
        when "today"
          return Date.current
        when "all_time", "this_year"
          # As of report - use current date for these
          return Date.current
        when "last_month"
          last_month = 1.month.ago.to_date
          return last_month.end_of_month
        when "this_month"
          return Date.current.end_of_month
        when "custom"
          # Use user-provided as_of_date or default to end of month
          return parse_single_report_date(params[:as_of_date]) || Date.current.end_of_month
        else
          # Check if it's a specific month (e.g. "2026-03")
          if date_preset =~ /\A\d{4}-\d{2}\z/
            return Date.parse("#{date_preset}-01").end_of_month
          end
        end
      end

      # Fallback: use as_of_date param or date param or default
      parse_single_report_date(params[:as_of_date]) || parse_single_report_date(params[:date]) || current_hotel.business_date_for || Date.current
    end

    def default_report_date_preset
      "today"
    end

    def authorize_view_reports!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_reports", hotel: current_hotel)
    end

    def authorize_view_payouts!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_payouts", hotel: current_hotel)
    end

    def parse_date_param(value)
      return if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def financial_performance_export_service
      @financial_performance_export_service ||= HotelPortal::Reports::FinancialPerformanceExportService.new(
        hotel: current_hotel,
        start_date: @start_date,
        end_date: @end_date,
        total_gross: @total_gross,
        total_margin: @total_margin,
        total_net: @total_net,
        booking_count: @booking_count,
        daily_data: Booking.daily_analytics(@start_date, @end_date, query: params[:q], base_scope: @base_bookings).index_by { |row| row[:date] }
      )
    end

    def breakdown_export_service
      @breakdown_export_service ||= HotelPortal::Reports::FinancialBreakdownExportService.new(
        bookings: @bookings,
        hotel: current_hotel,
        start_date: @start_date,
        end_date: @end_date
      )
    end

    def payouts_export_service
      history_scope = current_hotel.payout_batches_for_reports(start_date: @paid_start_date, end_date: @paid_end_date)
      HotelPortal::Reports::PayoutsExportService.new(
        hotel: current_hotel,
        active_tab: @active_tab,
        upcoming_bookings: @upcoming_bookings,
        upcoming_payout_amount: @upcoming_payout_amount,
        processing_batches: @processing_batches,
        payout_history: history_scope
      )
    end

    def payout_tab_label(tab)
      tab == "paid" ? "Paid History" : "Upcoming & Processing"
    end

    def folio_ledger_export_service
      @folio_ledger_export_service ||= FolioLedgerExportService.new(
        hotel: current_hotel,
        start_date: @start_date,
        end_date: @end_date
      )
    end
  end
end
