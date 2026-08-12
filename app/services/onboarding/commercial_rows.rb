# frozen_string_literal: true

module Onboarding
  # Shared row handling for the commercial sections, which all submit an
  # editable table of records backed by a per-hotel transaction code.
  #
  # The includer supplies `ENTRY_FIELDS` (the row keys it accepts),
  # `FAILURE_MESSAGE` (what to say when nothing more specific applies) and a
  # `RECORD_LABEL` used to number row errors.
  module CommercialRows
    extend ActiveSupport::Concern

    private

    def rows
      @rows ||= normalize_collection(@entries).map { |row| prepare_row(row.slice(*self.class::ENTRY_FIELDS)) }
    end

    # Hook for a section that fills in a field its table no longer asks for.
    # Rows are prepared in submission order, so a generator can take account of
    # what the rows before it have already claimed.
    def prepare_row(row) = row

    # An owner setting a property up is naming what they sell or what they take
    # off a bill, not keeping the books, so those tables do not ask for an
    # accounting code. A row typed from scratch gets one derived from its name
    # here rather than at save time, so the duplicate check and the per-hotel
    # unique index both see the value that will be stored. Rows that already
    # have a code — an adopted seeded code, or a record saved earlier — carry it
    # through untouched. Sections opt in from `prepare_row`; the ones whose
    # table still asks for a code leave it alone.
    def derived_code_row(row, fallback:)
      return row if row["id"].present? || row["transaction_code_id"].present?
      return row if row["code"].to_s.strip.present? || row["name"].to_s.strip.blank? || discarded?(row)

      row.merge("code" => generated_code(row["name"], fallback: fallback))
    end

    def generated_code(name, fallback:)
      base = normalize_code(name).first(10).delete_suffix("_").presence || fallback
      candidate = base
      suffix = 2

      while claimed_codes.include?(candidate)
        candidate = "#{base.first(9 - suffix.to_s.length).delete_suffix('_')}_#{suffix}"
        suffix += 1
      end

      claimed_codes << candidate
      candidate
    end

    def claimed_codes
      @claimed_codes ||= @hotel.transaction_codes.pluck(:code).map { |code| normalize_code(code) }.to_set
    end

    def retained_rows
      @retained_rows ||= rows.reject { |row| discarded?(row) || blank_row?(row) }
    end

    def discarded_rows
      @discarded_rows ||= rows.select { |row| discarded?(row) && row["id"].present? }
    end

    def discarded?(row) = ActiveModel::Type::Boolean.new.cast(row["_destroy"])

    # A row the owner never filled in — the trailing blank the table renders so
    # there is always somewhere to type.
    def blank_row?(row)
      row["id"].blank? && row["name"].to_s.strip.blank? && row["code"].to_s.strip.blank?
    end

    def normalize_collection(value)
      collection = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h.values : (value.is_a?(Hash) ? value.values : Array(value))
      collection.map { |item| (item.respond_to?(:to_unsafe_h) ? item.to_unsafe_h : item.to_h).deep_stringify_keys }
    end

    # The same rule the domain Save services apply, so a collision is detected
    # against the value that will actually be stored.
    def normalize_code(value)
      value.to_s.strip.upcase.gsub(/[^A-Z0-9]+/, "_").gsub(/_+/, "_").delete_prefix("_").delete_suffix("_")
    end

    # Rows are saved one at a time inside a single transaction, so a duplicate
    # would be caught by the per-hotel uniqueness validation anyway. Catching it
    # here first is what lets the message name the code rather than a row.
    def duplicate_code_error
      return @duplicate_code_error if defined?(@duplicate_code_error)

      codes = retained_rows.map { |row| normalize_code(row["code"]) }.reject(&:blank?)
      duplicate = codes.tally.find { |_code, count| count > 1 }&.first
      @duplicate_code_error =
        ("#{self.class::RECORD_LABEL} codes must be unique. #{duplicate} is used more than once." if duplicate)
    end

    def row_error(index, message) = "#{self.class::RECORD_LABEL} #{index + 1}: #{message}"

    def fail_transaction!(message)
      @error = message.presence || self.class::FAILURE_MESSAGE
      raise ActiveRecord::Rollback
    end
  end
end
