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
      return Result.new(preference: nil, visible_columns:, error: "Keep at least one column visible.") if visible_columns.empty?

      preference = ReportViewPreference.find_or_initialize_by(
        hotel:,
        user:,
        report_key: "housekeeping_tasks"
      )
      preference.visible_columns = visible_columns
      preference.save!
      Result.new(preference:, visible_columns:, error: nil)
    rescue ActiveRecord::RecordInvalid => error
      Result.new(preference:, visible_columns:, error: error.record.errors.full_messages.to_sentence)
    end

    private

    attr_reader :hotel, :user, :visible_columns
  end
end
