# frozen_string_literal: true

module Onboarding
  class ExtendAvailability
    Result = ApplicationResult.define(:start_date, :end_date, :record_count)

    def self.call(...) = new(...).call

    def initialize(hotel:, submission:, actor:, today:)
      @hotel = hotel
      @submission = submission
      @actor = actor
      @today = today
    end

    def call
      _, submitted_end = CompareSubmission.coverage_dates(@submission)
      start_date = [ @today, submitted_end + 1.day ].max
      end_date = @today + 364.days
      record_count = 0
      appended_start = nil
      appended_end = nil
      affected_rooms = []

      Hotel.transaction(requires_new: true) do
        @hotel.lock!
        @hotel.room_types.order(:id).each do |room|
          existing_dates = room.room_inventories.where(date: start_date..end_date).pluck(:date)
          missing_dates = (start_date..end_date).to_a - existing_dates
          next if missing_dates.empty?

          source = room.room_inventories.find_by(date: submitted_end)
          unless source&.valid? && source.quantity <= room.quantity
            raise ArgumentError, "#{room.name} has missing or invalid availability on the submitted end date. Request changes before continuing."
          end

          rows = missing_dates.map do |date|
            { room_type_id: room.id, date:, quantity: source.quantity, status: source.status, available_room_numbers: [] }
          end
          # These rows copy validated inventory. Bulk insertion avoids per-date
          # ARI callbacks; one synchronization request follows the outer commit.
          RoomInventory.insert_all!(rows)
          record_count += rows.size
          appended_start = [ appended_start, missing_dates.min ].compact.min
          appended_end = [ appended_end, missing_dates.max ].compact.max
          affected_rooms << room.id
          @hotel.inventory_audit_logs.create!(
            room_type: room, user: @actor, action_type: "bulk_inventory_update",
            old_value: {},
            new_value: { start_date: missing_dates.min, end_date: missing_dates.max, quantity: source.quantity, status: source.status },
            metadata: { source: "onboarding_availability_extension", submission_id: @submission.id, record_count: rows.size }
          )
        end

        if affected_rooms.any? && @hotel.preferred_channel_manager.present?
          ActiveRecord.after_all_transactions_commit do
            ChannelManagers::SyncJob.perform_later(
              @hotel.id, appended_start, appended_end,
              sync_availability: true, sync_rates: false, sync_restrictions: false,
              room_type_ids: affected_rooms, rate_plan_ids: []
            )
          end
        end
      end

      Result.success(start_date: appended_start, end_date: appended_end, record_count:)
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      Result.failure(e.message, start_date: nil, end_date: nil, record_count: 0)
    end
  end
end
