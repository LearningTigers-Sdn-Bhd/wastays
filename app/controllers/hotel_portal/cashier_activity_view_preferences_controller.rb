# frozen_string_literal: true

module HotelPortal
  class CashierActivityViewPreferencesController < HotelPortal::BaseController
    before_action :authorize_view_reports!

    def update
      result = ReportViewPreferences::Save.new(
        hotel: current_hotel,
        user: current_user,
        report_key: "daily_report_cashier_activity",
        columns: HotelPortal::Reports::CashierActivityColumns,
        visible_columns: params[:visible_columns]
      ).call

      if result.success?
        render json: { visible_columns: result.visible_columns }
      else
        render json: { error: result.error }, status: :unprocessable_content
      end
    end

    def destroy
      columns = ReportViewPreferences::Read.new(
        hotel: current_hotel,
        user: current_user,
        report_key: "daily_report_cashier_activity",
        columns: HotelPortal::Reports::CashierActivityColumns
      ).reset!
      render json: { visible_columns: columns }
    end

    private

    def authorize_view_reports!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_reports", hotel: current_hotel)
    end
  end
end
