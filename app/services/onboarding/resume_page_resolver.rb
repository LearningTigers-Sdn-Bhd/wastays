# frozen_string_literal: true

module Onboarding
  class ResumePageResolver
    def initialize(hotel:)
      @hotel = hotel
    end

    def call
      InitializeProgress.new(hotel: @hotel).call if @hotel.onboarding_sections.size < SectionCatalog.keys.size
      states = @hotel.onboarding_sections.index_by(&:section_key)

      current = SectionCatalog.all.find { |section| !states.fetch(section.key).resolved? }
      current || SectionCatalog.fetch("review")
    end
  end
end
