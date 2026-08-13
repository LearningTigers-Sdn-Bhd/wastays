# frozen_string_literal: true

module RatePlans
  # Removes one custom-plan assignment without leaving an unsellable plan or
  # deleting the channel-side rate plan mapping without notifying the channel.
  class RemoveRoomType
    Result = Data.define(:removed, :error) do
      def success? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(rate_plan:, room_type:)
      @rate_plan = rate_plan
      @room_type = room_type
    end

    def call
      return failure("Standard Rate room categories cannot be changed.") if rate_plan.standard_rate?
      return failure("This rate plan must keep at least one room category.") if rate_plan.room_type_rate_plans.count <= 1
      if rate_plan.booking_rooms.exists?(room_type_id: room_type.id)
        return failure("#{room_type.name} cannot be removed because existing bookings use this rate plan.")
      end

      assignment = rate_plan.room_type_rate_plans.find_by(room_type: room_type)
      return failure("#{room_type.name} is not assigned to this rate plan.") unless assignment

      mapping = assignment.channel_mapping
      delete_options = if mapping.present? && mapping.external_id != "pending"
        { hotel_id: rate_plan.hotel_id, external_id: mapping.external_id }
      end

      assignment.destroy!
      # Deleting the channel-side rate plan is irreversible, so it waits for the
      # local delete to commit rather than firing inside a transaction a caller
      # may still roll back. Runs immediately when there is no transaction.
      ActiveRecord.after_all_transactions_commit { enqueue_channel_delete(delete_options) }
      Result.new(removed: assignment, error: nil)
    rescue ActiveRecord::RecordNotDestroyed => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    attr_reader :rate_plan, :room_type

    def failure(message) = Result.new(removed: nil, error: message)

    def enqueue_channel_delete(options)
      return if options.blank?
      return if rate_plan.hotel.preferred_channel_manager.blank?
      return unless rate_plan.channex_syncable?

      ChannelManagers::SyncStructureJob.perform_later("RoomTypeRatePlan", nil, "delete", options)
    end
  end
end
