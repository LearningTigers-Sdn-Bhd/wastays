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
end
