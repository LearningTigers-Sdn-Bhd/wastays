# frozen_string_literal: true

require "set"

module HotelPortal
  module Reports
    # Holds the checkbox selection of a grouped report table. A selection is a
    # set of record ids, a set of whole groups, and a set of ids that the user
    # cleared inside a selected group.
    class RecordSelection
      def initialize(records:, record_id:, group_key:, ids: nil, group_values: nil, excluded_ids: nil)
        @records = records
        @record_id = record_id
        @group_key = group_key
        @submitted_ids = integer_set(ids)
        @submitted_group_values = Array(group_values).map(&:to_s).to_set
        @submitted_excluded_ids = integer_set(excluded_ids)
      end

      def ids = @ids ||= submitted_ids & allowed_ids
      def group_values = @group_values ||= submitted_group_values & allowed_group_values
      def excluded_ids = @excluded_ids ||= submitted_excluded_ids & allowed_ids
      def selected? = submitted_ids.any? || submitted_group_values.any?
      def record_selected?(id) = selected_ids.include?(id.to_i)
      def selected_count = selected_ids.size

      def selected_ids
        @selected_ids ||= begin
          grouped = records.filter_map { |record| id_of(record) if group_values.include?(key_of(record)) }.to_set
          ((ids | grouped) - excluded_ids) & allowed_ids
        end
      end

      def group_fully_selected?(group_records)
        group_ids = group_records.map { |record| id_of(record) }.to_set
        group_ids.any? && selected_ids.superset?(group_ids)
      end

      def group_partially_selected?(group_records)
        count = group_records.count { |record| record_selected?(id_of(record)) }
        count.positive? && count < group_records.size
      end

      def id_group_keys = keys_for(ids)
      def excluded_id_group_keys = keys_for(excluded_ids)

      private

      attr_reader :records, :submitted_ids, :submitted_group_values, :submitted_excluded_ids

      def id_of(record) = @record_id.call(record)
      def key_of(record) = @group_key.call(record)
      def allowed_ids = @allowed_ids ||= records.map { |record| id_of(record) }.to_set
      def allowed_group_values = @allowed_group_values ||= records.map { |record| key_of(record) }.to_set

      def keys_for(wanted)
        records.filter_map do |record|
          [ id_of(record).to_s, key_of(record) ] if wanted.include?(id_of(record))
        end.to_h
      end

      def integer_set(values)
        Array(values).filter_map { |value| Integer(value, exception: false) }.to_set
      end
    end
  end
end
