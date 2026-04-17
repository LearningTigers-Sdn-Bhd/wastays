require "csv"

class BookingExportService
  def initialize(bookings)
    @bookings = bookings
  end

  def generate_breakdown_csv
    attributes = %w[confirmation_token guest_name status check_in check_out total_amount margin_rate margin_amount net_amount currency]

    CSV.generate(headers: true) do |csv|
      csv << attributes.map(&:titleize)

      @bookings.each do |booking|
        csv << [
          booking.confirmation_token,
          booking.guest_name,
          booking.status,
          booking.check_in,
          booking.check_out,
          booking.total_amount,
          booking.margin_rate,
          booking.margin_amount,
          booking.net_amount,
          booking.currency
        ]
      end
    end
  end
end
