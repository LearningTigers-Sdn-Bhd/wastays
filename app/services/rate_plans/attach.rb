# frozen_string_literal: true

module RatePlans
  # Resolves one reusable custom rate plan and attaches it to all explicitly
  # selected rooms. Pricing is initialized per room; no cross-room form or
  # shared occupancy matrix is involved.
  class Attach
    Result = Data.define(:rate_plan, :attached_rooms, :error) do
      def success? = error.nil?
      def attached_count = attached_rooms.size
    end

    def self.call(...) = new(...).call

    def initialize(hotel:, rate_plan_name:, room_type_ids:, rate_plan_id: nil, user: nil)
      @hotel = hotel
      @rate_plan_id = rate_plan_id
      @rate_plan_name = rate_plan_name
      @room_type_ids = Array(room_type_ids).filter_map { |id| Integer(id, exception: false) }.uniq
      @user = user
    end

    def call
      previous_skip_ari_sync = Thread.current[:skip_ari_sync]
      return failure("Select at least one room category.") if room_type_ids.empty?

      rooms = load_rooms
      return failure("One or more selected room categories are not available for this property.") unless rooms.size == room_type_ids.size

      resolution = nil
      attached_rooms = []

      Thread.current[:skip_ari_sync] = true
      ActiveRecord::Base.transaction do
        resolution = RatePlans::Resolve.call(
          hotel: hotel,
          rate_plan_id: rate_plan_id,
          rate_plan_name: rate_plan_name
        )
        raise AttachmentError, resolution.error unless resolution.success?

        rooms.each do |room|
          next if resolution.rate_plan.room_type_rate_plans.exists?(room_type_id: room.id)

          RatePlans::BootstrapAssignment.call!(rate_plan: resolution.rate_plan, room_type: room)
          attached_rooms << room
        end
      end

      enqueue_channel_sync_after_commit(resolution.rate_plan, attached_rooms)
      Result.new(rate_plan: resolution.rate_plan, attached_rooms: attached_rooms, error: nil)
    rescue AttachmentError => e
      failure(e.message)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      failure(record_error(e))
    ensure
      Thread.current[:skip_ari_sync] = previous_skip_ari_sync
    end

    private

    AttachmentError = Class.new(StandardError)

    attr_reader :hotel, :rate_plan_id, :rate_plan_name, :room_type_ids, :user

    def load_rooms
      hotel.room_types.where(id: room_type_ids).order(:id).to_a
    end

    def enqueue_channel_sync_after_commit(rate_plan, rooms)
      return if rooms.empty?

      room_ids = rooms.map(&:id)
      ActiveRecord.after_all_transactions_commit do
        ChannelManagers::SyncRatePlanAri.call(rate_plan: rate_plan, room_type_ids: room_ids)
      end
    end

    def record_error(error)
      return error.record.errors.full_messages.to_sentence if error.respond_to?(:record)

      "That rate plan is already attached to one of the selected room categories."
    end

    def failure(message)
      Result.new(rate_plan: nil, attached_rooms: [], error: message)
    end
  end
end
