module PayoutEngine
  class GenerateWeeklyBatches
    def self.call
      new.call
    end

    def call
      # Cycle: Saturday to Friday
      # If running on Friday night/Saturday morning:
      # period_end = Last Friday
      # period_start = Saturday before that Friday

      end_date = last_friday
      start_date = end_date - 6.days

      puts "Generating payout batches for period: #{start_date} to #{end_date}"

      Booking.transaction do
        eligible_bookings = Booking.completed
                                   .where(payout_batch_id: nil)
                                   .where(checked_out_at: start_date.beginning_of_day..end_date.end_of_day)

        if eligible_bookings.empty?
          puts "No eligible bookings found for this period."
          return
        end

        batches_created = 0
        eligible_bookings.group_by(&:hotel_id).each do |hotel_id, bookings|
          total_net = bookings.sum { |b| b.net_amount || 0 }

          batch = PayoutBatch.create!(
            hotel_id: hotel_id,
            amount: total_net,
            status: "pending",
            period_start: start_date,
            period_end: end_date
          )

          bookings.each do |booking|
            booking.update!(payout_batch: batch, payout_status: "processing")
            Bookings::RecordAuditLog.call!(
              auditable: booking,
              action_type: "payout_processing",
              source: "system",
              metadata: { "payout_batch_id" => batch.id }
            )
          end

          batches_created += 1
          puts "Created batch for Hotel ##{hotel_id}: RM #{total_net} (#{bookings.count} bookings)"
        end

        puts "Total batches created: #{batches_created}"
      end
    end

    private

    def last_friday
      date = Date.current
      date -= 1 while !date.friday?
      date
    end
  end
end
