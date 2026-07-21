# frozen_string_literal: true

require "csv"
require "set"

module HotelPortal
  class ReportsController < HotelPortal::BaseController
    include FinancialFiltering
    include ReportDateFiltering

    PAYOUT_TABS = %w[upcoming paid].freeze
    GUEST_REPORT_TABS = %w[arrivals in_house departures checkout registration_cards bibo meal_prep].freeze
    EXTRA_CHARGE_REPORT_TABS = %w[fb non_fb].freeze
    DAILY_REPORT_TABS = %w[overview revenue cashier].freeze
    TAX_COMPLIANCE_TABS = %w[tourism_tax sst non_national].freeze
    DAILY_REVENUE_FILTER_KEYS = %i[q transaction_type category transaction_code_id posting_source reversal_status].freeze

    before_action :authorize_view_reports!, only: %i[index breakdown daily_occupancy daily_report daily_revenue_cell daily_revenue_source_bookings outstanding_balance deposit_liability guest_reports folio_ledger journal_batches tax_compliance refund_report extra_charge]
    before_action :authorize_view_payouts!, only: %i[payouts]
    before_action -> { require_feature!("daily_occupancy_revenue") }, only: %i[daily_occupancy]
    before_action -> { require_feature!("arrivals_departures_list") }, only: %i[guest_reports]
    before_action -> { require_feature!("outstanding_balance_noshow") }, only: %i[outstanding_balance]
    before_action -> { require_feature!("booking_source_analysis") }, only: %i[breakdown]
    before_action -> { require_feature!("revenue_allocation_per_night") }, only: %i[daily_report daily_revenue_cell daily_revenue_source_bookings]
    before_action -> { require_feature!("excel_pdf_export") }, if: -> { %i[csv xls xlsx pdf].include?(request.format.symbol) }

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
      append_breadcrumb({ label: payout_tab_label(@active_tab), tab_label: true, tabs_id: "payout-tabs" }) if request.format.html?

      @upcoming_bookings = current_hotel.bookings.unbatched_upcoming(cutoff_date)
      @upcoming_payout_amount = current_hotel.upcoming_payout_amount(cutoff_date)

      @processing_batches = current_hotel.payout_batches.where(status: "processing")

      paid_range_start, paid_range_end = parse_report_date_range_param(params[:paid_date_range])
      @paid_start_date = paid_range_start || parse_date_param(params[:paid_start_date])
      @paid_end_date = paid_range_end || parse_date_param(params[:paid_end_date])
      @paid_end_date = @paid_start_date if @paid_start_date && @paid_end_date && @paid_end_date < @paid_start_date

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

    def daily_report
      @report_start_date, @report_end_date = parse_report_date_range
      @daily_report_tab = params[:tab].presence_in(DAILY_REPORT_TABS) || "overview"

      @revenue_report = HotelPortal::Reports::DailyRevenueReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date,
        date_preset: params[:date_preset]
      ).call

      @cashier_report = HotelPortal::Reports::CashierSalesReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date
      ).call

      if @daily_report_tab == "revenue"
        prepare_charge_register
      else
        prepare_empty_charge_register
      end
      prepare_cashier_lists

      respond_to do |format|
        format.html
        format.csv do
          csv = HotelPortal::Reports::DailyReportCsvExportService.new(
            tab: @daily_report_tab,
            revenue_report: @revenue_report,
            cashier_report: @cashier_report,
            charge_register: @charge_register_result.rows
          ).generate
          send_data csv,
            filename: "daily-report-#{@daily_report_tab}-#{@revenue_report.start_date}-#{@revenue_report.end_date}.csv",
            type: "text/csv"
        end
        format.xlsx do
          workbook = HotelPortal::Reports::DailyReportExcelExportService.new(
            hotel: current_hotel,
            tab: @daily_report_tab,
            revenue_report: @revenue_report,
            cashier_report: @cashier_report,
            charge_register: @charge_register_result.rows
          ).generate
          send_data workbook,
            filename: "daily-report-#{@daily_report_tab}-#{@revenue_report.start_date}-#{@revenue_report.end_date}.xlsx",
            type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::DailyReportPdfExportService.new(
            hotel: current_hotel,
            tab: @daily_report_tab,
            revenue_report: @revenue_report,
            cashier_report: @cashier_report,
            charge_register: @charge_register_result.rows
          ).generate
          send_data pdf,
            filename: "daily-report-#{@daily_report_tab}-#{@revenue_report.start_date}-#{@revenue_report.end_date}.pdf",
            type: "application/pdf",
            disposition: "attachment"
        end
      end
    end

    def daily_revenue_cell
      date = parse_date_param(params[:date])
      return head :bad_request if date.nil?

      monthly = params[:date_preset].to_s == "this_year"
      start_date = monthly ? date.beginning_of_month : date
      end_date = monthly ? date.end_of_month : date

      @detail = HotelPortal::Reports::DailyRevenueCellDetail.new(
        hotel: current_hotel,
        start_date: start_date,
        end_date: end_date,
        category: params[:category]
      ).call
    end

    def daily_revenue_source_bookings
      @report_start_date, @report_end_date = parse_report_date_range

      @detail = HotelPortal::Reports::DailyRevenueSourceBookings.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date,
        source: params[:source]
      ).call
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

    def guest_reports
      @active_guest_report_tab = GUEST_REPORT_TABS.include?(params[:tab]) ? params[:tab] : "arrivals"
      if %w[bibo meal_prep].include?(@active_guest_report_tab) && !current_hotel.allow_boat_information?
        @active_guest_report_tab = "arrivals"
      end
      @report_start_date, @report_end_date = parse_report_date_range

      @report = HotelPortal::Reports::ArrivalsDeparturesReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date
      ).call

      @bibo_report = HotelPortal::Reports::BiboReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date
      ).call

      if @active_guest_report_tab == "meal_prep"
        params[:meal_type] = "breakfast" unless %w[breakfast lunch dinner].include?(params[:meal_type])
        @meal_prep_report = HotelPortal::Reports::MealPrepReport.new(
          hotel: current_hotel,
          start_date: @report_start_date,
          end_date: @report_end_date,
          meal_type: params[:meal_type]
        ).call

        full_report = HotelPortal::Reports::MealPrepReport.new(
          hotel: current_hotel,
          start_date: @report_start_date,
          end_date: @report_end_date
        ).call

        @meal_prep_counts = {
          "breakfast" => full_report.records.select { |r| r[:meal_type].downcase.include?("breakfast") }.sum { |r| r[:pax] },
          "lunch"     => full_report.records.select { |r| r[:meal_type].downcase.include?("lunch") }.sum { |r| r[:pax] },
          "dinner"    => full_report.records.select { |r| r[:meal_type].downcase.include?("dinner") }.sum { |r| r[:pax] }
        }
      end

      load_guest_registration_cards(start_date: @report_start_date, end_date: @report_end_date)

      report_to_export = if @active_guest_report_tab == "bibo"
        @bibo_report
      elsif @active_guest_report_tab == "meal_prep"
        @meal_prep_report
      else
        @report
      end

      filename_suffix = if @active_guest_report_tab == "meal_prep"
        "meal-prep-#{params[:meal_type]}"
      else
        @active_guest_report_tab.tr("_", "-")
      end

      respond_to do |format|
        format.html
        format.csv do
          return head :not_acceptable if @active_guest_report_tab == "registration_cards"

          csv = HotelPortal::Reports::ArrivalsDeparturesCsvExportService.new(report: report_to_export, tab: @active_guest_report_tab).generate
          send_data csv,
            filename: "guest-reports-#{filename_suffix}-#{@report.start_date}-#{@report.end_date}.csv",
            type: "text/csv"
        end
        format.any(:xls) do
          return head :not_acceptable if @active_guest_report_tab == "registration_cards"

          workbook = HotelPortal::Reports::ArrivalsDeparturesExcelExportService.new(report: report_to_export, tab: @active_guest_report_tab).generate
          send_data workbook,
            filename: "guest-reports-#{filename_suffix}-#{@report.start_date}-#{@report.end_date}.xls",
            type: "application/vnd.ms-excel",
            disposition: "attachment"
        end
        format.pdf do
          return head :not_acceptable if @active_guest_report_tab == "registration_cards"

          pdf = HotelPortal::Reports::ArrivalsDeparturesPdfExportService.new(hotel: current_hotel, report: report_to_export, tab: @active_guest_report_tab).generate
          send_data pdf,
            filename: "guest-reports-#{filename_suffix}-#{@report.start_date}-#{@report.end_date}.pdf",
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

    def tax_compliance
      @active_tax_compliance_tab = TAX_COMPLIANCE_TABS.include?(params[:tab]) ? params[:tab] : "tourism_tax"
      @report_start_date, @report_end_date = parse_report_date_range
      @report = tax_compliance_report

      filename_suffix = @active_tax_compliance_tab.tr("_", "-")

      respond_to do |format|
        format.html
        format.csv do
          send_data tax_compliance_csv_export_service.generate,
            filename: "tax-compliance-#{filename_suffix}-#{@report.start_date}-#{@report.end_date}.csv",
            type: "text/csv"
        end
        format.xlsx do
          send_data tax_compliance_excel_export_service.generate,
            filename: "tax-compliance-#{filename_suffix}-#{@report.start_date}-#{@report.end_date}.xlsx",
            type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            disposition: "attachment"
        end
        format.pdf do
          send_data tax_compliance_pdf_export_service.generate,
            filename: "tax-compliance-#{filename_suffix}-#{@report.start_date}-#{@report.end_date}.pdf",
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

    private

    def tax_compliance_report
      case @active_tax_compliance_tab
      when "sst"
        HotelPortal::Reports::SstReport.new(
          hotel: current_hotel,
          start_date: @report_start_date,
          end_date: @report_end_date,
          date_preset: params[:date_preset]
        ).call
      when "non_national"
        HotelPortal::Reports::NonNationalReport.new(
          hotel: current_hotel,
          start_date: @report_start_date,
          end_date: @report_end_date
        ).call
      else
        HotelPortal::Reports::TourismTaxReport.new(
          hotel: current_hotel,
          start_date: @report_start_date,
          end_date: @report_end_date
        ).call
      end
    end

    def tax_compliance_csv_export_service
      case @active_tax_compliance_tab
      when "sst" then HotelPortal::Reports::SstCsvExportService.new(report: @report)
      when "non_national" then HotelPortal::Reports::NonNationalCsvExportService.new(report: @report)
      else HotelPortal::Reports::TourismTaxCsvExportService.new(report: @report)
      end
    end

    def tax_compliance_excel_export_service
      case @active_tax_compliance_tab
      when "sst" then HotelPortal::Reports::SstExcelExportService.new(hotel: current_hotel, report: @report)
      when "non_national" then HotelPortal::Reports::NonNationalExcelExportService.new(hotel: current_hotel, report: @report)
      else HotelPortal::Reports::TourismTaxExcelExportService.new(hotel: current_hotel, report: @report)
      end
    end

    def tax_compliance_pdf_export_service
      case @active_tax_compliance_tab
      when "sst" then HotelPortal::Reports::SstPdfExportService.new(hotel: current_hotel, report: @report)
      when "non_national" then HotelPortal::Reports::NonNationalPdfExportService.new(hotel: current_hotel, report: @report)
      else HotelPortal::Reports::TourismTaxPdfExportService.new(hotel: current_hotel, report: @report)
      end
    end

    def prepare_empty_charge_register
      @transaction_filters = params.permit(*DAILY_REVENUE_FILTER_KEYS).to_h.compact_blank
      @charge_register_result = HotelPortal::Reports::DailyReportChargeRegister::Result.new(
        rows: [].freeze,
        amount_total: 0.to_d,
        tax_total: 0.to_d
      )
    end

    def prepare_charge_register
      query = HotelPortal::Reports::DailyRevenueTransactionQuery.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date,
        filters: params.permit(*DAILY_REVENUE_FILTER_KEYS),
        transaction_types: %w[charge adjustment]
      )
      @transaction_filters = query.filters
      @transaction_codes = current_hotel.transaction_codes.active.order(:name, :code)
      transactions = query.call
      @charge_register_result = if query.filters.empty?
        HotelPortal::Reports::DailyReportChargeRegister.new(transactions: transactions).call
      else
        filtered_charge_register_result(transactions.ids.to_set)
      end
      @charge_register_count = @charge_register_result.rows.size
      return unless request.format.html?

      @charge_register_rows = Kaminari.paginate_array(@charge_register_result.rows)
        .page(params[:page]).per(50)
    end

    def filtered_charge_register_result(visible_transaction_ids)
      result = HotelPortal::Reports::DailyReportChargeRegister.new(
        transactions: HotelPortal::Reports::DailyRevenueTransactionQuery.new(
          hotel: current_hotel,
          start_date: @report_start_date,
          end_date: @report_end_date,
          transaction_types: %w[charge adjustment]
        ).call
      ).call
      rows = result.rows.select do |row|
        row.transaction_ids.any? { |transaction_id| visible_transaction_ids.include?(transaction_id) }
      end.freeze
      HotelPortal::Reports::DailyReportChargeRegister::Result.new(
        rows: rows,
        amount_total: rows.sum(&:signed_amount),
        tax_total: rows.sum(&:tax_amount)
      )
    end

    def prepare_cashier_lists
      return unless request.format.html?

      @advance_transactions = @cashier_report.advance_scope.page(params[:advance_page]).per(50)
      @advance_rows = @advance_transactions.map do |transaction|
        HotelPortal::Reports::DailyReportTransactionRow.new(
          transaction,
          settlement_mode: @cashier_report.mode_by_transaction_id[transaction.id]
        )
      end
      @settlement_transactions = @cashier_report.settlement_scope.page(params[:settlement_page]).per(50)
      @settlement_rows = @settlement_transactions.map do |transaction|
        HotelPortal::Reports::DailyReportTransactionRow.new(
          transaction,
          settlement_mode: @cashier_report.mode_by_transaction_id[transaction.id]
        )
      end
    end

    def load_guest_registration_cards(start_date: nil, end_date: nil)
      @status_filter = params[:status].to_s
      @grc_query = params[:q].to_s.strip

      query_obj = HotelPortal::GuestRegistrationCardsQuery.new(
        hotel: current_hotel,
        start_date: start_date,
        end_date: end_date,
        status: @status_filter,
        query: @grc_query,
        page: params[:page]
      )

      @grc_total_count = query_obj.total_count
      @grc_signed_count = query_obj.signed_count
      @grc_draft_count = query_obj.draft_count
      @grc_cards = query_obj.results
    end

    def authorize_view_reports!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_reports", hotel: current_hotel)
    end

    def authorize_view_payouts!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_payouts", hotel: current_hotel)
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
