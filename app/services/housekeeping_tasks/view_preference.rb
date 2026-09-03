# frozen_string_literal: true

module HousekeepingTasks
  class ViewPreference
    REPORT_KEY = "housekeeping_tasks"

    def initialize(hotel:, user:)
      @hotel = hotel
      @user = user
    end

    def visible_columns
      preference.visible_columns
    end

    def reset!
      preference.reset!
    end

    private

    attr_reader :hotel, :user

    def preference
      ReportViewPreferences::Read.new(hotel:, user:, report_key: REPORT_KEY, columns: Columns)
    end
  end
end
