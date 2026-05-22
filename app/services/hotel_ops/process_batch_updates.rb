# frozen_string_literal: true

module HotelOps
  class ProcessBatchUpdates
    def initialize(hotel:, updates:, user:)
      @hotel = hotel
      @updates = updates
      @user = user
    end

    def call
      errors = []
      min_date = nil
      max_date = nil
      sync_availability = false
      sync_rates = false
      sync_restrictions = false
      room_type_windows = {}
      rate_plan_windows = {}
      rate_plan_fields = {}

      ActiveRecord::Base.transaction do
        Thread.current[:skip_ari_sync] = true

        @updates.each do |selection|
          # 1. Track overall date range and sync types for a single final sync
          s_date = selection[:start_date]&.to_date
          e_date = selection[:end_date]&.to_date

          # Guard against missing dates
          next unless s_date && e_date

          min_date = [ min_date, s_date ].compact.min
          max_date = [ max_date, e_date ].compact.max

          sync_availability ||= cast_boolean(selection[:apply_inventory])
          sync_rates ||= cast_boolean(selection[:apply_rates])
          sync_restrictions ||= cast_boolean(selection[:apply_restrictions])

          # 2. Map granular ID-to-window for surgical sync
          Array(selection[:room_type_ids]).each do |id|
            win = room_type_windows[id.to_s] || { "min" => s_date.to_s, "max" => e_date.to_s }
            win["min"] = [ win["min"].to_date, s_date ].min.to_s
            win["max"] = [ win["max"].to_date, e_date ].max.to_s
            room_type_windows[id.to_s] = win
          end

          Array(selection[:rate_plan_ids]).each do |id|
            win = rate_plan_windows[id.to_s] || { "min" => s_date.to_s, "max" => e_date.to_s }
            win["min"] = [ win["min"].to_date, s_date ].min.to_s
            win["max"] = [ win["max"].to_date, e_date ].max.to_s
            rate_plan_windows[id.to_s] = win

            # Track which fields were modified for this rate plan
            rate_plan_fields[id.to_s] ||= Set.new
            rate_plan_fields[id.to_s].merge(Array(selection[:modified_fields]))
          end

          # 3. Apply the actual changes
          result = HotelOps::ApplyInventoryDashboardSelection.new(
            hotel: @hotel,
            selection: selection,
            user: @user,
            skip_sync: true
          ).call

          unless result[:success]
            errors << result[:error]
            raise ActiveRecord::Rollback
          end
        end

        # 4. Trigger a single background sync job covering the entire updated range
        if @hotel.preferred_channel_manager.present? && min_date && max_date
          ChannelManagers::SyncJob.perform_later(
            @hotel.id,
            min_date,
            max_date,
            sync_availability: sync_availability,
            sync_rates: sync_rates,
            sync_restrictions: sync_restrictions,
            room_type_ids: room_type_windows,
            rate_plan_ids: rate_plan_windows,
            rate_plan_fields: rate_plan_fields.transform_values(&:to_a)
          )
        end
      end

      if errors.empty?
        { success: true, message: "All changes synced successfully." }
      else
        { success: false, error: errors.join(", ") }
      end
    rescue => e
      Rails.logger.error "Batch ARI Sync Failed: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
      { success: false, error: "Unexpected error: #{e.message}" }
    ensure
      Thread.current[:skip_ari_sync] = nil
    end

    private

    def cast_boolean(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end
  end
end
