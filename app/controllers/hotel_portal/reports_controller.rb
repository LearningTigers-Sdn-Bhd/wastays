# frozen_string_literal: true

require "csv"
require "set"

module HotelPortal
  class ReportsController < HotelPortal::ReportsBaseController
    include FinancialFiltering
    include ReportDateFiltering

    PAYOUT_TABS = %w[upcoming paid].freeze
    GUEST_REPORT_TABS = %w[arrivals in_house departures checkout police_report registration_cards bibo meal_prep].freeze
    MEAL_PREP_ALL = "all"
    BIBO_ALL = "all"
    EXTRA_CHARGE_REPORT_TABS = %w[fb non_fb].freeze
    DAILY_REPORT_TABS = %w[overview revenue cashier].freeze
    TAX_COMPLIANCE_TABS = %w[tourism_tax sst non_national].freeze
    OTA_SETTLEMENT_STATUS_FILTERS = {
      "all" => nil,
      "outstanding" => %w[awaiting_ota_settlement virtual_card_not_ready ready_to_charge partially_received underpaid unknown],
      "received" => %w[received],
      "overpaid" => %w[overpaid],
      "needs_attention" => %w[needs_attention failed],
      "cancelled" => %w[cancelled]
    }.freeze
    DAILY_REVENUE_FILTER_KEYS = %i[q transaction_type category transaction_code_id posting_source reversal_status].freeze

    before_action :authorize_view_reports!, only: %i[index breakdown daily_occupancy daily_report daily_revenue_cell daily_revenue_source_bookings outstanding_balance deposit_liability guest_reports folio_ledger journal_batches tax_compliance refund_report extra_charge channel_settlements]
    before_action :authorize_view_payouts!, only: %i[payouts]
    before_action -> { require_feature!("daily_occupancy_revenue") }, only: %i[daily_occupancy]
    before_action -> { require_feature!("arrivals_departures_list") }, only: %i[guest_reports]
    before_action -> { require_feature!("outstanding_balance_noshow") }, only: %i[outstanding_balance]
    before_action -> { require_feature!("booking_source_analysis") }, only: %i[breakdown]
    before_action -> { require_feature!("revenue_allocation_per_night") }, only: %i[daily_report daily_revenue_cell daily_revenue_source_bookings]
    before_action -> { require_feature!("excel_pdf_export") }, if: -> { %i[csv xlsx pdf].include?(request.format.symbol) }

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
      if @date_preset == "this_year"
        revenue_by_month = @daily_data.group_by { |date, _| date.beginning_of_month }
        @daily_data = (1..12).map do |month|
          month_start = Date.new(@start_date.year, month, 1)
          [ month_start, revenue_by_month.fetch(month_start, []).sum { |_, gross| gross } ]
        end
      end
      @paginated_daily_data = Kaminari.paginate_array(@daily_data).page(params[:page]).per(25)
      prepare_reports_summary

      respond_to do |format|
        format.html
        format.csv do
          csv = HotelPortal::Reports::FinancialPerformanceCsvExportService.new(
            hotel: current_hotel,
            report: financial_performance_export_result
          ).generate
          send_data csv,
            filename: "financial-performance-#{@start_date}-#{@end_date}.csv",
            type: "text/csv; charset=utf-8"
        end
        format.xlsx do
          workbook = HotelPortal::Reports::FinancialPerformanceExcelExportService.new(
            hotel: current_hotel,
            report: financial_performance_export_result
          ).generate
          send_data workbook,
            filename: "financial-performance-#{@start_date}-#{@end_date}.xlsx",
            type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::FinancialPerformancePdfExportService.new(
            hotel: current_hotel,
            report: financial_performance_export_result,
            prepared_by: current_user.name
          ).generate
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
          csv = HotelPortal::Reports::PayoutsCsvExportService.new(
            hotel: current_hotel,
            report: payouts_export_result
          ).generate
          send_data csv,
            filename: "payouts-#{@active_tab}-#{Date.current}.csv",
            type: "text/csv; charset=utf-8"
        end
        format.xlsx do
          workbook = HotelPortal::Reports::PayoutsExcelExportService.new(
            hotel: current_hotel,
            report: payouts_export_result
          ).generate
          send_data workbook,
            filename: "payouts-#{@active_tab}-#{Date.current}.xlsx",
            type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::PayoutsPdfExportService.new(
            hotel: current_hotel,
            report: payouts_export_result,
            prepared_by: current_user.name
          ).generate
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
          @grouped_bookings = @paginated_bookings.group_by do |booking|
            date = booking.created_at.to_date
            @date_preset == "this_year" ? date.beginning_of_month : date
          end.transform_values do |bookings|
            bookings.map { |b| HotelPortal::BookingFinancialPresenter.new(b) }
          end
        end
        format.csv do
          send_data HotelPortal::Reports::FinancialBreakdownCsvExportService.new(hotel: current_hotel, report: financial_breakdown_export_result).generate,
            filename: "financial-breakdown-#{@start_date}-#{@end_date}.csv",
            type: "text/csv; charset=utf-8"
        end
        format.xlsx do
          workbook = HotelPortal::Reports::FinancialBreakdownExcelExportService.new(hotel: current_hotel, report: financial_breakdown_export_result).generate
          send_data workbook,
            filename: "financial-breakdown-#{@start_date}-#{@end_date}.xlsx",
            type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::FinancialBreakdownPdfExportService.new(
            hotel: current_hotel, report: financial_breakdown_export_result, prepared_by: current_user.name
          ).generate
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
            type: "text/csv; charset=utf-8"
        end
        format.xlsx do
          workbook = HotelPortal::Reports::DailyOccupancyExcelExportService.new(hotel: current_hotel, report: @report).generate
          send_data workbook,
            filename: "daily-occupancy-#{@report.start_date}-#{@report.end_date}.xlsx",
            type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::DailyOccupancyPdfExportService.new(
            hotel: current_hotel, report: @report, prepared_by: current_user.name
          ).generate
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
        end_date: @report_end_date,
        **cashier_report_filters
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
            cashier_report: cashier_export_report,
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
            cashier_report: cashier_export_report,
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
            cashier_report: cashier_export_report,
            charge_register: @charge_register_result.rows,
            prepared_by: current_user.name
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
            type: "text/csv; charset=utf-8"
        end
        format.xlsx do
          workbook = HotelPortal::Reports::OutstandingBalanceExcelExportService.new(hotel: current_hotel, report: @report).generate
          send_data workbook,
            filename: "outstanding-balance-#{@report.start_date}-#{@report.end_date}.xlsx",
            type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::OutstandingBalancePdfExportService.new(
            hotel: current_hotel, report: @report, prepared_by: current_user.name
          ).generate
          send_data pdf,
            filename: "outstanding-balance-#{@report.start_date}-#{@report.end_date}.pdf",
            type: "application/pdf",
            disposition: "attachment"
        end
      end
    end

    def channel_settlements
      @report_start_date, @report_end_date = parse_report_date_range
      @settlement_statuses = OTA_SETTLEMENT_STATUS_FILTERS.keys
      @settlement_status = params[:status].presence_in(@settlement_statuses) || "all"
      @settlement_sources = current_hotel.channel_settlements
        .where(collection_by: "ota")
        .includes(:booking_source)
        .map(&:booking_source)
        .uniq(&:id)
        .sort_by { |source| source.label.downcase }
      @settlement_currencies = current_hotel.channel_settlements
        .where(collection_by: "ota")
        .distinct
        .order(:currency)
        .pluck(:currency)
      @report = HotelPortal::Reports::ChannelSettlementReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date,
        query: params[:q],
        source: params[:source],
        currency: params[:currency],
        statuses: OTA_SETTLEMENT_STATUS_FILTERS.fetch(@settlement_status)
      ).call
      @settlement_rows = Kaminari.paginate_array(@report.detail_rows).page(params[:page]).per(25)

      respond_to do |format|
        format.html
        format.csv do
          csv = HotelPortal::Reports::ChannelSettlementCsvExportService.new(report: @report).generate
          send_data csv,
            filename: "ota-settlements-#{@report.start_date}-#{@report.end_date}.csv",
            type: "text/csv; charset=utf-8"
        end
        format.xlsx do
          workbook = HotelPortal::Reports::ChannelSettlementExcelExportService.new(hotel: current_hotel, report: @report).generate
          send_data workbook,
            filename: "ota-settlements-#{@report.start_date}-#{@report.end_date}.xlsx",
            type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
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
            type: "text/csv; charset=utf-8"
        end
        format.xlsx do
          workbook = HotelPortal::Reports::DepositLiabilityExcelExportService.new(hotel: current_hotel, report: @report).generate
          send_data workbook,
            filename: "deposit-liability-#{@report.as_of_date}.xlsx",
            type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::DepositLiabilityPdfExportService.new(
            hotel: current_hotel, report: @report, prepared_by: current_user.name
          ).generate
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

      # Built once: the tab strip counts every leg, the table shows the selected
      # one. Both come off this single pass.
      @bibo_full = HotelPortal::Reports::BiboReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date
      ).call

      @bibo_report = @bibo_full

      @police_report = HotelPortal::Reports::PoliceReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date
      ).call

      # Built once and reused: the tab strip needs a count on every tab, and the
      # meal tabs each need one too. Both are derived from this single pass.
      if current_hotel.allow_boat_information?
        @meal_prep_full = HotelPortal::Reports::MealPrepReport.new(
          hotel: current_hotel,
          start_date: @report_start_date,
          end_date: @report_end_date
        ).call
      end

      if @active_guest_report_tab == "bibo"
        legs = HotelPortal::Reports::BiboReport::LEG_KEYS
        params[:leg] = BIBO_ALL unless legs.include?(params[:leg])
        # "All" keeps both directions in one report; each leg becomes its own section.
        @bibo_report = @bibo_full.for_leg(params[:leg] == BIBO_ALL ? nil : params[:leg])
        @bibo_counts = legs.index_with { |leg| @bibo_full.count_for(leg) }
          .merge(BIBO_ALL => @bibo_full.total_count)
      end

      if @active_guest_report_tab == "meal_prep"
        meals = HotelPortal::Reports::MealPrepReport::MEALS
        params[:meal_type] = MEAL_PREP_ALL unless meals.include?(params[:meal_type])
        # "All" keeps every meal in one report; each meal becomes its own section.
        @meal_prep_report = @meal_prep_full.for_meal(params[:meal_type] == MEAL_PREP_ALL ? nil : params[:meal_type])
        @meal_prep_counts = meals.index_with { |meal| @meal_prep_full.pax_for(meal) }
          .merge(MEAL_PREP_ALL => @meal_prep_full.total_pax)
      end

      load_guest_registration_cards(start_date: @report_start_date, end_date: @report_end_date)

      report_to_export = if @active_guest_report_tab == "police_report"
        @police_report
      elsif @active_guest_report_tab == "bibo"
        @bibo_report
      elsif @active_guest_report_tab == "meal_prep"
        @meal_prep_report
      else
        @report
      end

      filename_suffix = if @active_guest_report_tab == "meal_prep"
        "meal-prep-#{params[:meal_type]}"
      elsif @active_guest_report_tab == "bibo"
        "bibo-#{params[:leg].tr('_', '-')}"
      else
        @active_guest_report_tab.tr("_", "-")
      end

      respond_to do |format|
        format.html
        format.csv do
          return head :not_acceptable if @active_guest_report_tab == "registration_cards"

          csv = if @active_guest_report_tab == "police_report"
            HotelPortal::Reports::PoliceReportCsvExportService.new(report: @police_report).generate
          else
            HotelPortal::Reports::ArrivalsDeparturesCsvExportService.new(report: report_to_export, tab: @active_guest_report_tab).generate
          end
          send_data csv,
            filename: "guest-reports-#{filename_suffix}-#{@report.start_date}-#{@report.end_date}.csv",
            type: "text/csv; charset=utf-8"
        end
        format.xlsx do
          return head :not_acceptable if @active_guest_report_tab == "registration_cards"

          workbook = if @active_guest_report_tab == "police_report"
            HotelPortal::Reports::PoliceReportExcelExportService.new(hotel: current_hotel, report: @police_report).generate
          else
            HotelPortal::Reports::ArrivalsDeparturesExcelExportService.new(hotel: current_hotel, report: report_to_export, tab: @active_guest_report_tab).generate
          end
          send_data workbook,
            filename: "guest-reports-#{filename_suffix}-#{@report.start_date}-#{@report.end_date}.xlsx",
            type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            disposition: "attachment"
        end
        format.pdf do
          return head :not_acceptable if @active_guest_report_tab == "registration_cards"

          pdf = if @active_guest_report_tab == "police_report"
            HotelPortal::Reports::PoliceReportPdfExportService.new(
              hotel: current_hotel, report: @police_report, prepared_by: current_user.name
            ).generate
          else
            HotelPortal::Reports::ArrivalsDeparturesPdfExportService.new(
              hotel: current_hotel, report: report_to_export, tab: @active_guest_report_tab,
              prepared_by: current_user.name
            ).generate
          end
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
            type: "text/csv; charset=utf-8"
        end
        format.xlsx do
          send_data service.generate_xlsx,
            filename: "folio-ledger-#{@start_date}-#{@end_date}.xlsx",
            type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            disposition: "attachment"
        end
        format.pdf do
          send_data service.generate_pdf(prepared_by: current_user.name),
            filename: "folio-ledger-#{@start_date}-#{@end_date}.pdf",
            type: "application/pdf",
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
          @journal_summary = HotelPortal::Reports::JournalBatchExportTable.new(batches: @batches)
          @paginated_batches = @batches.page(params[:page]).per(25)
        end
        format.csv do
          csv = HotelPortal::Reports::JournalBatchCsvExportService.new(batches: @batches).generate
          send_data csv,
            filename: "journal-batches-#{@report_start_date}-#{@report_end_date}.csv",
            type: "text/csv; charset=utf-8"
        end
        format.xlsx do
          workbook = HotelPortal::Reports::JournalBatchExcelExportService.new(
            hotel: current_hotel, batches: @batches, start_date: @report_start_date, end_date: @report_end_date
          ).generate
          send_data workbook,
            filename: "journal-batches-#{@report_start_date}-#{@report_end_date}.xlsx",
            type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::JournalBatchPdfExportService.new(
            hotel: current_hotel, batches: @batches, start_date: @report_start_date,
            end_date: @report_end_date, prepared_by: current_user.name
          ).generate
          send_data pdf,
            filename: "journal-batches-#{@report_start_date}-#{@report_end_date}.pdf",
            type: "application/pdf",
            disposition: "attachment"
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
            type: "text/csv; charset=utf-8"
        end
        format.xlsx do
          workbook = HotelPortal::Reports::RefundReportExcelExportService.new(hotel: current_hotel, report: @report).generate
          send_data workbook,
            filename: "refund-report-#{@report.start_date}-#{@report.end_date}.xlsx",
            type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::RefundReportPdfExportService.new(
            hotel: current_hotel, report: @report, prepared_by: current_user.name
          ).generate
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
        tab: @active_extra_charge_tab,
        date_preset: params[:date_preset]
      ).call

      respond_to do |format|
        format.html
        format.csv do
          csv = HotelPortal::Reports::ExtraChargeCsvExportService.new(hotel: current_hotel, report: @report).generate
          send_data csv,
            filename: extra_charge_export_filename("csv"),
            type: "text/csv"
        end
        format.xlsx do
          workbook = HotelPortal::Reports::ExtraChargeExcelExportService.new(hotel: current_hotel, report: @report).generate
          send_data workbook,
            filename: extra_charge_export_filename("xlsx"),
            type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            disposition: "attachment"
        end
        format.pdf do
          pdf = HotelPortal::Reports::ExtraChargePdfExportService.new(
            hotel: current_hotel, report: @report, prepared_by: current_user.name
          ).generate
          send_data pdf,
            filename: extra_charge_export_filename("pdf"),
            type: "application/pdf",
            disposition: "attachment"
        end
      end
    end

    private

    def prepare_reports_summary
      refund_report = HotelPortal::Reports::RefundReport.new(
        hotel: current_hotel,
        start_date: @start_date,
        end_date: @end_date,
        date_preset: @date_preset
      ).call
      extra_charge_total = %w[fb non_fb].sum do |tab|
        HotelPortal::Reports::ExtraChargeReport.new(
          hotel: current_hotel,
          start_date: @start_date,
          end_date: @end_date,
          tab: tab,
          date_preset: @date_preset
        ).call.totals[:total_amount]
      end
      outstanding_report = HotelPortal::Reports::OutstandingBalanceReport.new(
        hotel: current_hotel,
        start_date: @start_date,
        end_date: @end_date
      ).call
      deposit_liability_report = HotelPortal::Reports::DepositLiabilityReport.new(
        hotel: current_hotel,
        as_of_date: @end_date
      ).call
      tourism_tax_report = HotelPortal::Reports::TourismTaxReport.new(
        hotel: current_hotel,
        start_date: @start_date,
        end_date: @end_date
      ).call
      sst_report = HotelPortal::Reports::SstReport.new(
        hotel: current_hotel,
        start_date: @start_date,
        end_date: @end_date,
        date_preset: @date_preset
      ).call
      non_national_report = HotelPortal::Reports::NonNationalReport.new(
        hotel: current_hotel,
        start_date: @start_date,
        end_date: @end_date
      ).call
      guest_operations_report = HotelPortal::Reports::ArrivalsDeparturesReport.new(
        hotel: current_hotel,
        start_date: @start_date,
        end_date: @end_date
      ).call
      journal_table = HotelPortal::Reports::JournalBatchExportTable.new(
        batches: current_hotel.journal_batches
                              .where(business_date: @start_date..@end_date)
                              .includes(:entries)
                              .order(business_date: :desc)
      )

      @reports_summary = {
        financial: {
          refunds: refund_report.totals[:total_amount],
          extra_charges: extra_charge_total,
          outstanding: outstanding_report.totals[:outstanding_amount],
          deposit_liability: deposit_liability_report.totals[:remaining_liability]
        },
        tax_compliance: {
          tourism_tax: tourism_tax_report.totals[:total_collected],
          sst: sst_report.totals[:sst_amount],
          non_national_guests: non_national_report.totals[:guest_count]
        },
        guest_operations: {
          arrivals: guest_operations_report.arrival_count,
          in_house: guest_operations_report.in_house_count,
          departures: guest_operations_report.departure_count,
          checkouts: guest_operations_report.checkout_count
        },
        accounting: {
          batches: journal_table.batch_count,
          debit: journal_table.total_debit,
          credit: journal_table.total_credit
        }
      }
    end

    def extra_charge_export_filename(extension)
      tab = @active_extra_charge_tab.tr("_", "-")
      "extra-charge-report-#{tab}-#{@report.start_date}-#{@report.end_date}.#{extension}"
    end

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
      when "sst" then HotelPortal::Reports::SstPdfExportService.new(hotel: current_hotel, report: @report, prepared_by: current_user.name)
      when "non_national" then HotelPortal::Reports::NonNationalPdfExportService.new(hotel: current_hotel, report: @report, prepared_by: current_user.name)
      else HotelPortal::Reports::TourismTaxPdfExportService.new(hotel: current_hotel, report: @report, prepared_by: current_user.name)
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

    def cashier_report_filters
      {
        start_time: params[:cashier_start_time],
        end_time: params[:cashier_end_time]
      }
    end

    def cashier_export_report
      return @cashier_report unless params[:selected_transaction_ids].present?

      HotelPortal::Reports::CashierSalesReport.new(
        hotel: current_hotel,
        start_date: @report_start_date,
        end_date: @report_end_date,
        **cashier_report_filters,
        transaction_ids: Array(params[:selected_transaction_ids])
      ).call
    end

    def prepare_cashier_lists
      return unless request.format.html?

      @cashier_transactions = Kaminari.paginate_array(@cashier_report.cash_transactions)
                                      .page(params[:cashier_page]).per(50)
      @cashier_rows = cashier_rows_for(@cashier_transactions)
      @non_cash_rows = cashier_rows_for(@cashier_report.non_cash_transactions)
    end

    def cashier_rows_for(transactions)
      transactions.map do |transaction|
        HotelPortal::Reports::DailyReportTransactionRow.new(
          transaction,
          settlement_mode: @cashier_report.mode_by_transaction_id[transaction.id],
          section: @cashier_report.section_by_transaction_id[transaction.id],
          origin: @cashier_report.non_cash_origin_by_transaction_id[transaction.id]
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
      allowed = current_user.has_permission?("view_payouts", hotel: current_hotel) && !current_hotel.hide_payout_reports?
      raise Pundit::NotAuthorizedError unless allowed
    end

    def financial_performance_export_result
      @financial_performance_export_result ||= HotelPortal::Reports::FinancialPerformanceExportResult.new(
        start_date: @start_date,
        end_date: @end_date,
        totals: {
          gross: @total_gross,
          margin: @total_margin,
          net: @total_net,
          booking_count: @booking_count
        },
        rows: Booking.daily_analytics(@start_date, @end_date, query: params[:q], base_scope: @base_bookings).map do |row|
          {
            date: row.fetch(:date),
            booking_count: row.fetch(:booking_count),
            gross: row.fetch(:revenue),
            margin: row.fetch(:margin),
            net: row.fetch(:net)
          }
        end
      )
    end

    def financial_breakdown_export_result
      @financial_breakdown_export_result ||= HotelPortal::Reports::FinancialBreakdownExportResult.new(
        start_date: @start_date,
        end_date: @end_date,
        rows: @bookings.map do |booking|
          {
            booking_reference: booking.confirmation_token,
            guest_name: booking.guest_name,
            status: booking.status,
            check_in: booking.check_in,
            check_out: booking.check_out,
            gross: booking.total_amount,
            taxes: booking.tax_total,
            margin: booking.margin_amount,
            net: booking.net_amount,
            currency: booking.currency.presence || current_hotel.default_currency
          }
        end
      )
    end

    def payouts_export_result
      @payouts_export_result ||= begin
      history_scope = current_hotel.payout_batches_for_reports(start_date: @paid_start_date, end_date: @paid_end_date)
      HotelPortal::Reports::PayoutsExportResult.new(
        active_tab: @active_tab,
        upcoming_rows: @upcoming_bookings.map do |booking|
          {
            booking_reference: booking.confirmation_token,
            checked_out_at: booking.checked_out_at,
            status: booking.payout_status,
            net_amount: booking.net_amount
          }
        end,
        processing_rows: @processing_batches.map do |batch|
          {
            period_start: batch.period_start,
            period_end: batch.period_end,
            status: batch.status,
            reference: batch.payout_reference,
            net_amount: batch.amount
          }
        end,
        paid_rows: history_scope.map do |batch|
          {
            period_start: batch.period_start,
            period_end: batch.period_end,
            settled_at: batch.payout_at,
            status: batch.status,
            reference: batch.payout_reference,
            net_amount: batch.amount
          }
        end,
        paid_start_date: @paid_start_date,
        paid_end_date: @paid_end_date
      )
      end
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
