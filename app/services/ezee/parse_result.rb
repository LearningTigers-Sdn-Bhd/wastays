# frozen_string_literal: true

module Ezee
  # What a layout parser hands back: the rows, the count the file states about
  # itself, and either warnings or a single error that refuses the file.
  ParseResult = Struct.new(:rows, :declared_total, :warnings, :error, :layout, keyword_init: true) do
    def success? = error.blank?
  end
end
