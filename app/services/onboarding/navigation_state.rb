# frozen_string_literal: true

module Onboarding
  class NavigationState
    Entry = Data.define(:definition, :record, :available)

    attr_reader :entries

    def initialize(hotel:)
      @hotel = hotel
    end

    def call
      InitializeProgress.new(hotel: @hotel).call
      records = @hotel.onboarding_sections.index_by(&:section_key)

      @entries = SectionCatalog.all.map do |definition|
        Entry.new(
          definition: definition,
          record: records.fetch(definition.key),
          available: records.fetch(definition.key).resolved? || prerequisites_resolved?(definition, records)
        )
      end.freeze
      self
    end

    def fetch(section_key)
      entries.find { |entry| entry.definition.key == section_key.to_s } ||
        raise(KeyError, "Unknown onboarding section: #{section_key}")
    end

    def resume_entry
      entries.find { |entry| !entry.record.resolved? } || fetch("review")
    end

    def previous_entry(section_key)
      entry_at_offset(section_key, -1)
    end

    def next_entry(section_key)
      entry_at_offset(section_key, 1)
    end

    private

    def prerequisites_resolved?(definition, records)
      definition.prerequisites.all? { |key| records.fetch(key).resolved? }
    end

    def entry_at_offset(section_key, offset)
      index = entries.index { |entry| entry.definition.key == section_key.to_s }
      return unless index

      entries[index + offset] if (index + offset).between?(0, entries.length - 1)
    end
  end
end
