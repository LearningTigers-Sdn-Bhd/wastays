# frozen_string_literal: true

module HousekeepingTasks
  class ViewPreference
    REPORT_KEY = "housekeeping_tasks"

    def initialize(hotel:, user:)
      @hotel = hotel
      @user = user
    end

    def visible_columns
      stored = ReportViewPreference.find_by(hotel:, user:, report_key: REPORT_KEY)&.visible_columns
      normalized = Columns.normalize(stored)
      normalized.presence || Columns::KEYS
    end

    def reset!
      ReportViewPreference.where(hotel:, user:, report_key: REPORT_KEY).delete_all
      Columns::KEYS
    end

    private

    attr_reader :hotel, :user
  end
end
