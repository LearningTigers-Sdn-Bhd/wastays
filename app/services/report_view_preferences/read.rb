# frozen_string_literal: true

module ReportViewPreferences
  class Read
    def initialize(hotel:, user:, report_key:, columns:)
      @hotel = hotel
      @user = user
      @report_key = report_key
      @columns = columns
    end

    def visible_columns
      stored = ReportViewPreference.find_by(hotel:, user:, report_key:)&.visible_columns
      columns.normalize(stored).presence || columns::DEFAULT_KEYS
    end

    def reset!
      ReportViewPreference.where(hotel:, user:, report_key:).delete_all
      columns::DEFAULT_KEYS
    end

    private

    attr_reader :hotel, :user, :report_key, :columns
  end
end
