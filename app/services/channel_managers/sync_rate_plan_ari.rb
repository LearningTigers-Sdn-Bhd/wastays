# frozen_string_literal: true

module ChannelManagers
  # Pushes a rate plan's structure and rates to the channel manager once per
  # save, rather than once per room category.
  #
  # RoomTypeRatePlan#trigger_ari_sync fires per row, so saving a plan across N
  # categories enqueued N structure jobs and N rate syncs — every one of the
  # latter covering the same 500-day window for the same rate plan. The
  # structure jobs are genuinely per-mapping and stay, but the rate push
  # collapses into a single job carrying every affected room type.
  #
  # Callers suppress the per-row callback with Thread.current[:skip_ari_sync]
  # (the same switch the inventory dashboard bulk writes use) and call this
  # after the transaction commits.
  class SyncRatePlanAri
    SYNC_WINDOW_DAYS = 499

    def self.call(...) = new(...).call

    def initialize(rate_plan:, room_type_ids:)
      @rate_plan = rate_plan
      @room_type_ids = Array(room_type_ids).uniq
    end

    def call
      return if room_type_ids.empty?
      return unless ChannelManagers::ConnectionState.provisioned?(rate_plan.hotel)

      enqueue_structure_syncs
      enqueue_rate_sync
    end

    private

    attr_reader :rate_plan, :room_type_ids

    # One per mapping: the channel manager needs each room type / rate plan
    # pair to exist before rates for it can be pushed.
    def enqueue_structure_syncs
      scoped_assignments.find_each do |rtrp|
        next unless rate_plan.channex_syncable?(room_type: rtrp.room_type)

        ChannelManagers::SyncStructureJob.perform_later("RoomTypeRatePlan", rtrp.id, "sync")
      end
    end

    def scoped_assignments
      rate_plan.room_type_rate_plans.includes(:room_type, :occupancy_prices).where(room_type_id: room_type_ids)
    end

    def enqueue_rate_sync
      ChannelManagers::SyncJob.perform_later(
        rate_plan.hotel_id,
        Date.current,
        Date.current + SYNC_WINDOW_DAYS.days,
        sync_availability: false,
        sync_rates: true,
        sync_restrictions: true,
        room_type_ids: room_type_ids,
        rate_plan_ids: [ rate_plan.id ]
      )
    end
  end
end
