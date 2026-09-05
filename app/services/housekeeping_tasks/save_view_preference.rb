# frozen_string_literal: true

module HousekeepingTasks
  class SaveViewPreference
    Result = Data.define(:preference, :visible_columns, :error) do
      def success? = error.nil?
    end

    def initialize(hotel:, user:, visible_columns:)
      @hotel = hotel
      @user = user
      @visible_columns = Columns.normalize(visible_columns)
    end

    def call
      result = ReportViewPreferences::Save.new(
        hotel:, user:, report_key: "housekeeping_tasks", columns: Columns, visible_columns:
      ).call
      Result.new(preference: result.preference, visible_columns: result.visible_columns, error: result.error)
    end

    private

    attr_reader :hotel, :user, :visible_columns
  end
end
