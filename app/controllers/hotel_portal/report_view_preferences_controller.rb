# frozen_string_literal: true

module HotelPortal
  # Saves and restores the visible columns of a report table. Each report
  # subclasses this and declares its preference key and its column module.
  class ReportViewPreferencesController < HotelPortal::BaseController
    before_action :authorize_view_reports!

    class_attribute :report_key, instance_writer: false
    class_attribute :report_columns, instance_writer: false

    def update
      result = ReportViewPreferences::Save.new(
        **preference_scope, visible_columns: params[:visible_columns]
      ).call

      if result.success?
        render json: { visible_columns: result.visible_columns }
      else
        render json: { error: result.error }, status: :unprocessable_content
      end
    end

    def destroy
      render json: { visible_columns: ReportViewPreferences::Read.new(**preference_scope).reset! }
    end

    private

    def preference_scope
      { hotel: current_hotel, user: current_user, report_key:, columns: report_columns }
    end

    def authorize_view_reports!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_reports", hotel: current_hotel)
    end
  end
end
