# frozen_string_literal: true

module CorporatePortal
  class ArStatementsController < CorporatePortal::BaseController
    helper_method :statement_pdf_filename

    before_action :set_relationship, only: %i[show pdf]

    def index
      @presenter = CorporatePortal::AccountsReceivable::StatementsIndexPresenter.new(account: current_user.account, params: params, request: request)
    end

    def show
      report = build_report
      @presenter = CorporatePortal::AccountsReceivable::StatementPresenter.new(report: report, params: params, request: request)
      append_breadcrumb @relationship.hotel.name, corporate_ar_statement_path(@relationship)

    rescue ::Reports::AccountsReceivable::GenerateStatementRecords::InvalidStatementError => e
      render_invalid_statement(e)
    end

    def pdf
      report = build_report
      document = ::Reports::AccountsReceivable::GenerateStatement.new(
        report: report,
        printed_by: current_user&.name
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
      @relationship = current_user.account.hotel_corporate_accounts.includes(:hotel).find(params[:id])
      @hotel_corporate_account = @relationship
    end

    def build_report
      ::Reports::AccountsReceivable::GenerateStatementRecords.call(
        hotel: @relationship.hotel,
        hotel_corporate_account: @relationship,
        start_date: params[:start_date].presence || default_start_date,
        end_date: params[:end_date].presence || business_date,
        currency: params[:currency]
      )
    end

    def available_currencies
      currencies = @relationship.ar_invoices.distinct.pluck(:currency) +
        @relationship.ar_payments.distinct.pluck(:currency)
      currencies << @relationship.credit_currency
      currencies.compact.map(&:to_s).reject(&:blank?).uniq.sort
    end

    def business_date
      @business_date ||= (@relationship.hotel.current_business_date || @relationship.hotel.business_date_for(Time.current)).to_date
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
        hotel_name: report.hotel.name,
        start_date: report.start_date,
        end_date: report.end_date,
        currency: report.currency
      )
    end

    def statement_pdf_filename(hotel_name:, start_date:, end_date:, currency:)
      hotel = hotel_name.parameterize.presence || "hotel"
      "account-statement-#{hotel}-#{start_date}-#{end_date}-#{currency}.pdf"
    end

    def render_invalid_statement(error)
      @statement_error = error.message
      @start_date = parsed_date_or_default(params[:start_date], default_start_date)
      @end_date = parsed_date_or_default(params[:end_date], business_date)
      @available_currencies = available_currencies
      @selected_currency = params[:currency].presence || @available_currencies.first
      render :show, status: :unprocessable_content
    end
  end
end
