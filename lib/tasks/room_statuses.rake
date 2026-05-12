# frozen_string_literal: true

namespace :room_statuses do
  desc "Backfill ready room statuses for configured room numbers"
  task backfill: :environment do
    created_count = 0

    RoomType.includes(:hotel).find_each do |room_type|
      Array(room_type.room_numbers).each do |room_number|
        room_number = room_number.to_s.strip
        next if room_number.blank?

        status = RoomStatus.find_or_create_by!(
          hotel: room_type.hotel,
          room_type: room_type,
          room_number: room_number
        ) do |room_status|
          room_status.status = "ready"
          room_status.last_changed_at = Time.current
          room_status.notes = "Backfilled from configured room numbers"
        end

        created_count += 1 if status.previously_new_record?
      end
    end

    puts "Backfilled #{created_count} room statuses."
  end

  desc "Sync room statuses based on active/expired room blocks for today"
  task sync_daily: :environment do
    # 1. Find rooms that should be out_of_service today but aren't
    RoomBlock.active_on(Date.current).find_each do |block|
      room_status = block.hotel.room_statuses.find_or_create_by!(
        room_type: block.room_type,
        room_number: block.room_number
      )

      next if room_status.status == "out_of_service"

      Rooms::SetStatus.new(
        room_status: room_status,
        status: "out_of_service",
        user: block.user,
        reason: "Blocked: #{block.block_type} (#{block.reason})",
        event_type: "room_blocked_auto_status"
      ).call
    end

    # 2. Find rooms that are out_of_service but have no active blocks today
    # These are blocks that expired yesterday or were moved
    RoomStatus.where(status: "out_of_service").find_each do |room_status|
      has_active_block = room_status.hotel.room_blocks
                                    .active_on(Date.current)
                                    .where(room_type: room_status.room_type, room_number: room_status.room_number)
                                    .any?
      
      next if has_active_block

      Rooms::SetStatus.new(
        room_status: room_status,
        status: "pending_cleaning",
        user: nil, # System action
        reason: "Maintenance block expired",
        event_type: "room_block_removed_auto_status"
      ).call
    end
  end
end
