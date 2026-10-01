# frozen_string_literal: true

module Ezee
  # The front door of the importer: works out which eZee report layout a file
  # is and hands it to that layout's parser. Every parser returns the same rows,
  # so nothing after this knows which one ran.
  #
  # `layout` lets an operator override detection, for a file that was re-saved
  # and no longer looks like the original.
  class ParseFile
    PARSERS = {
      reservation_list: ReservationListParser,
      reservation_csv: ReservationCsvParser
    }.freeze
    LABELS = {
      reservation_list: "eZee Reservation List (.xls / .xlsx)",
      reservation_csv: "eZee reservation CSV"
    }.freeze

    def self.call(...) = new(...).call

    def initialize(path:, filename:, layout: nil)
      @path = path
      @filename = filename
      @layout = layout.to_s.presence&.to_sym
    end

    def call
      layout = @layout || LayoutDetector.call(path: @path, filename: @filename)
      return unknown_layout unless PARSERS.key?(layout)

      PARSERS.fetch(layout).call(path: @path, filename: @filename)
    end

    private

    def unknown_layout
      ParseResult.new(
        rows: [], warnings: [],
        error: "This file is not a recognised eZee report. Upload the Reservation List " \
               "(.xls or .xlsx) or the reservation CSV (it has \"Res. No\" and \"Business Source\" columns)."
      )
    end
  end
end
