# frozen_string_literal: true

require "csv"

module HotelPortal
  class ReportsController < HotelPortal::BaseController
    include FinancialFiltering

    before_action :authorize_view_reports!, only: %i[index breakdown daily_occupancy daily_revenue managers_flash outstanding_balance deposit_liability arrivals_departures folio_ledger journal_batches]
    before_action :authorize_view_payouts!, only: %i[payouts]

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
      @active_tab = params[:tab] || "upcoming"

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
        end_date: @report_end_date
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
        end_date: @report_end_date
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
        end_date: @report_end_date
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
      @report_as_of_date = parse_single_report_date(params[:as_of_date]) || parse_single_report_date(params[:date]) || current_hotel.business_date_for || Date.current
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
      @report_start_date, @report_end_date = parse_report_date_range
      @report = HotelPortal::Reports::ArrivalsDeparturesReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date
      ).call

      respond_to do |format|
        format.html
        format.csv do
          csv = HotelPortal::Reports::ArrivalsDeparturesCsvExportService.new(report: @report).generate
          send_data csv,
            filename: "arrivals-departures-#{@report.start_date}-#{@report.end_date}.csv",
            type: "text/csv"
        end
        format.any(:xls) do
          workbook = HotelPortal::Reports::ArrivalsDeparturesExcelExportService.new(report: @report).generate
          send_data workbook,
            filename: "arrivals-departures-#{@report.start_date}-#{@report.end_date}.xls",
            type: "application/vnd.ms-excel",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::ArrivalsDeparturesPdfExportService.new(hotel: current_hotel, report: @report).generate
          send_data pdf,
            filename: "arrivals-departures-#{@report.start_date}-#{@report.end_date}.pdf",
            type: "application/pdf",
            disposition: "attachment"
        end
      end
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

    private

    def parse_report_date_range
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

    def folio_ledger_export_service
      @folio_ledger_export_service ||= FolioLedgerExportService.new(
        hotel: current_hotel,
        start_date: @start_date,
        end_date: @end_date
      )
    end
  end
end
