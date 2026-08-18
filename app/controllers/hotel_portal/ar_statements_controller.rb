# frozen_string_literal: true

module HotelPortal
  class ArStatementsController < FinancialsBaseController
    helper_method :statement_pdf_filename

    before_action :authorize_view_reports!
    before_action :set_relationship, only: %i[show pdf]

    def index
      @presenter = HotelPortal::AccountsReceivable::StatementsIndexPresenter.new(hotel: current_hotel, params: params)
    end

    def show
      report = build_report
      @presenter = HotelPortal::AccountsReceivable::StatementPresenter.new(report: report, params: params)

    rescue ::Reports::AccountsReceivable::GenerateStatementRecords::InvalidStatementError => e
      render_invalid_statement(e)
    end

    def pdf
      report = build_report(include_invoice_details: detail_report?)
      document = ::Reports::AccountsReceivable::GenerateStatement.new(
        report: report,
        printed_by: current_user&.name,
        detail: detail_report?
      ).generate
      send_data document,
        filename: statement_filename(report),
        type: "application/pdf",
        disposition: "inline"
    rescue ::Reports::AccountsReceivable::GenerateStatementRecords::InvalidStatementError => e
      render plain: e.message, status: :unprocessable_content
    end

    private

    def set_relationship
      @hotel_corporate_account = current_hotel.hotel_corporate_accounts
        .includes(corporate_account: :users)
        .find(params[:id])
    end

    def build_report(include_invoice_details: false)
      ::Reports::AccountsReceivable::GenerateStatementRecords.call(
        hotel: current_hotel,
        hotel_corporate_account: @hotel_corporate_account,
        start_date: params[:start_date].presence || default_start_date,
        end_date: params[:end_date].presence || business_date,
        currency: params[:currency],
        include_invoice_details: include_invoice_details
      )
    end

    def detail_report?
      params[:report_type] == "detail"
    end

    def available_currencies
      currencies = @hotel_corporate_account.ar_invoices.distinct.pluck(:currency) +
        @hotel_corporate_account.ar_payments.distinct.pluck(:currency)
      currencies << @hotel_corporate_account.credit_currency
      currencies.compact.map(&:to_s).reject(&:blank?).uniq.sort
    end

    def business_date
      @business_date ||= (current_hotel.current_business_date || current_hotel.business_date_for(Time.current)).to_date
    end

    def default_start_date
      business_date.beginning_of_month
    end

    def parsed_date_or_default(value, fallback)
      Date.iso8601(value.to_s)
    rescue Date::Error
      fallback
    end

    def statement_filename(report)
      statement_pdf_filename(
        account_name: report.corporate_account.name,
        start_date: report.start_date,
        end_date: report.end_date,
        currency: report.currency
      )
    end

    def statement_pdf_filename(account_name:, start_date:, end_date:, currency:)
      account = account_name.parameterize.presence || "corporate-account"
      "account-statement-#{account}-#{start_date}-#{end_date}-#{currency}.pdf"
    end

    def render_invalid_statement(error)
      @statement_error = error.message
      @start_date = parsed_date_or_default(params[:start_date], default_start_date)
      @end_date = parsed_date_or_default(params[:end_date], business_date)
      @available_currencies = available_currencies
      @selected_currency = params[:currency].presence || @available_currencies.first
      render :show, status: :unprocessable_content
    end

    def authorize_view_reports!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_reports", hotel: current_hotel)
    end
  end
end
