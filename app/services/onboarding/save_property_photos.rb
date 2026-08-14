# frozen_string_literal: true

module Onboarding
  # The photos step has no form of its own: photos are already uploaded by the
  # time this runs, because the upload sheet commits them as they are chosen.
  # All this records is whether the property has met the one requirement.
  class SavePropertyPhotos
    Result = ApplicationResult.define(:section)

    def initialize(hotel:, actor:, complete:)
      @hotel = hotel
      @actor = actor
      @complete = complete
    end

    def call
      if @complete && !@hotel.property_photos_ready?
        return failure("Upload at least one photo of the property before continuing.")
      end

      transition(@complete ? "complete" : "in_progress")
    end

    private

    def transition(state)
      result = UpdateSection.new(
        hotel: @hotel,
        section_key: "property_photos",
        state: state,
        actor: @actor,
        metadata: { source: "property_photos" }
      ).call
      return Result.failure(result.error, section: result.section) unless result.success?

      Result.success(section: result.section)
    end

    def failure(message)
      Result.failure(message, section: @hotel.onboarding_sections.find_by(section_key: "property_photos"))
    end
  end
end
