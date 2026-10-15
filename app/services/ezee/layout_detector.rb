# frozen_string_literal: true

module Ezee
  # Says which eZee report an uploaded file is, so the operator does not have to.
  #
  # eZee exports the same reservations through different reports and each lays
  # the data out differently. A CSV is recognised by its header row; a
  # spreadsheet is the Crystal Reports Reservation List. Anything else is nil,
  # which the caller reports -- a file is never guessed at.
  class LayoutDetector
    LAYOUTS = %i[reservation_list reservation_csv].freeze
    SPREADSHEETS = %w[.xls .xlsx].freeze

    def self.call(...) = new(...).call

    def initialize(path:, filename:)
      @path = path.to_s
      @extension = File.extname(filename.to_s).downcase
    end

    def call
      return :reservation_list if SPREADSHEETS.include?(@extension)
      return :reservation_csv if @extension == ".csv" && ReservationCsvParser.recognises?(@path)

      nil
    end
  end
end
