# frozen_string_literal: true

module Attractions
  class Merge
    Result = ApplicationResult.define(:target, :merged_links_count)

    def self.call(source:, target:, reviewer: nil)
      new(source: source, target: target, reviewer: reviewer).call
    end

    def initialize(source:, target:, reviewer:)
      @source = source
      @target = target
      @reviewer = reviewer
    end

    def call
      return Result.failure("Select two different attractions.") if @source == @target
      return Result.failure("The source attraction was already merged.") if @source.merged_into_id.present?
      return Result.failure("The target attraction must be pending or approved.") unless @target.status_pending? || @target.status_approved?

      merged_links_count = 0
      Attraction.transaction do
        locked = Attraction.where(id: [ @source.id, @target.id ]).order(:id).lock.index_by(&:id)
        source = locked.fetch(@source.id)
        target = locked.fetch(@target.id)

        source.hotel_nearby_attractions.order(:id).find_each do |source_link|
          merge_link(source_link, target)
          merged_links_count += 1
        end

        source.update!(
          status: "archived",
          archived_from_status: source.status,
          merged_into: target,
          reviewed_by: @reviewer,
          reviewed_at: Time.current,
          review_note: "Merged into #{target.name}."
        )
      end

      Result.success(target: @target.reload, merged_links_count: merged_links_count)
    rescue ActiveRecord::RecordInvalid => error
      Result.failure(error.record.errors.full_messages.to_sentence)
    end

    private

    def merge_link(source_link, target)
      target_link = HotelNearbyAttraction.find_or_initialize_by(
        hotel_id: source_link.hotel_id,
        attraction: target
      )
      target_link.description = source_link.description if target_link.description.blank?
      target_link.created_at ||= source_link.created_at
      target_link.save!
      source_link.destroy!
    end
  end
end
