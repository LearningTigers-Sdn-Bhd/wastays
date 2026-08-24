# frozen_string_literal: true

module Attractions
  class FindOrCreateAndLink
    Result = ApplicationResult.define(:attraction, :hotel_nearby_attraction, :"created?", :"reused?")
    MAX_ATTEMPTS = 2

    def self.call(**attributes)
      new(**attributes).call
    end

    def initialize(hotel:, google_maps_url:, submitted_by: nil, description: nil, approve: false)
      @hotel = hotel
      @google_maps_url = google_maps_url
      @submitted_by = submitted_by
      @description = description
      @approve = approve
      @attempts = 0
    end

    def call
      parsed_result = GoogleMapsUrlParser.call(@google_maps_url)
      return Result.failure(parsed_result.error) unless parsed_result.success?

      @parsed = parsed_result.parsed
      create_or_link
    rescue ActiveRecord::RecordInvalid => error
      Result.failure(error.record.errors.full_messages.to_sentence)
    end

    private

    def create_or_link
      @attempts += 1
      Attraction.transaction do
        attraction = FindDuplicate.call(fingerprint: @parsed.fingerprint)
        return inactive_failure(attraction) if attraction&.status_rejected? || attraction&.status_archived?

        created = attraction.nil?
        attraction ||= create_attraction
        approve_pending!(attraction) if @approve
        link = link_attraction(attraction)

        Result.success(
          attraction: attraction,
          hotel_nearby_attraction: link,
          "created?": created,
          "reused?": !created
        )
      end
    rescue ActiveRecord::RecordNotUnique
      retry if @attempts < MAX_ATTEMPTS

      Result.failure("This attraction was changed by another request. Try again.")
    end

    def create_attraction
      Attraction.create!(
        name: @parsed.name,
        normalized_name: @parsed.normalized_name,
        google_maps_url: @parsed.google_maps_url,
        latitude: @parsed.latitude,
        longitude: @parsed.longitude,
        coordinate_fingerprint: @parsed.fingerprint,
        source_hotel: @hotel,
        submitted_by: @submitted_by,
        status: @approve ? "approved" : "pending",
        reviewed_by: @approve ? @submitted_by : nil,
        reviewed_at: @approve ? Time.current : nil
      )
    end

    def approve_pending!(attraction)
      return unless attraction.status_pending?

      attraction.update!(
        status: "approved",
        reviewed_by: @submitted_by,
        reviewed_at: Time.current,
        review_note: nil
      )
    end

    def link_attraction(attraction)
      link = HotelNearbyAttraction.find_or_initialize_by(hotel: @hotel, attraction: attraction)
      link.description = @description if @description.present?
      link.save!
      link
    end

    def inactive_failure(attraction)
      label = attraction.status_rejected? ? "rejected" : "archived"
      Result.failure("This attraction is #{label}. An administrator must review it before you can add it.")
    end
  end
end
