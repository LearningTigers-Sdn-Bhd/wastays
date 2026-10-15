# frozen_string_literal: true

module Onboarding
  # The photos step has no form of its own: photos are already uploaded by the
  # time this runs, because the upload sheet commits them as they are chosen.
  # Continuing records either uploaded photos or the decision to add none now.
  class SavePropertyPhotos
    Result = ApplicationResult.define(:section)

    def initialize(hotel:, actor:, complete:)
      @hotel = hotel
      @actor = actor
      @complete = complete
    end

    def call
      state = if !@complete
        "in_progress"
      elsif @hotel.photos.attached?
        "complete"
      else
        "skipped"
      end

      transition(state)
    end

    private

    def transition(state)
      metadata = { source: "property_photos" }
      metadata[:decision] = "no_photos_now" if state == "skipped"

      result = UpdateSection.new(
        hotel: @hotel,
        section_key: "property_photos",
        state: state,
        actor: @actor,
        metadata: metadata
      ).call
      return Result.failure(result.error, section: result.section) unless result.success?

      Result.success(section: result.section)
    end
  end
end
