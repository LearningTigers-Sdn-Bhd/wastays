# frozen_string_literal: true

module CorporatePortal
  class ArStatementsController < CorporatePortal::BaseController
    before_action :set_relationship, only: :show

    def index
      @presenter = CorporatePortal::AccountsReceivable::StatementsIndexPresenter.new(account: current_user.account, params: params)
    end

    def show
      report = build_report
      @presenter = CorporatePortal::AccountsReceivable::StatementPresenter.new(report: report, params: params)
      append_breadcrumb @relationship.hotel.name, corporate_ar_statement_path(@relationship)

      respond_to do |format|
        format.html
        format.pdf do
          pdf = ::Reports::AccountsReceivable::GenerateStatement.new(report: report, printed_by: current_user&.name).generate
          send_data pdf,
            filename: statement_filename(report),
            type: "application/pdf",
            disposition: "inline"
        end
      end
    rescue ::Reports::AccountsReceivable::GenerateStatementRecords::InvalidStatementError => e
      @statement_error = e.message
      @start_date = parsed_date_or_default(params[:start_date], default_start_date)
      @end_date = parsed_date_or_default(params[:end_date], business_date)
      @available_currencies = available_currencies
      @selected_currency = params[:currency].presence || @available_currencies.first

      respond_to do |format|
        format.html { render :show, status: :unprocessable_content }
        format.pdf { render plain: e.message, status: :unprocessable_content }
      end
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
      hotel = report.hotel_corporate_account.hotel.name.parameterize.presence || "hotel"
      "ar-statement-#{hotel}-#{report.start_date}-#{report.end_date}-#{report.currency}.pdf"
    end
  end
end
