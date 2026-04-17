require "csv"

class Admin::PayoutsController < Admin::BaseController
  def index
    # Friday cutoff logic (Friday end of day)
    cutoff_date = last_friday.end_of_day
    
    @eligible_bookings = Booking.completed
                                .where(payout_status: "pending")
                                .where("checked_out_at <= ?", cutoff_date)

    @payout_summary = @eligible_bookings.group_by(&:hotel_id).map do |hotel_id, bookings|
      hotel = Hotel.find(hotel_id)
      {
        hotel: hotel,
        booking_count: bookings.count,
        total_net: bookings.sum { |b| b.net_amount || 0 }
      }
    end
  end

  def export_maybank
    cutoff_date = last_friday.end_of_day
    bookings_to_process = Booking.completed
                                 .where(payout_status: "pending")
                                 .where("checked_out_at <= ?", cutoff_date)

    if bookings_to_process.empty?
      redirect_to admin_payouts_path, alert: "No eligible bookings for payout."
      return
    end

    csv_data = CSV.generate(headers: false) do |csv|
      # Maybank Template Headers (Based on image)
      csv << [ "Crediting Date (eg. dd/MM/yyyy)", Date.current.strftime("%d/%m/%Y") ]
      csv << [ "Payment Reference", "WASTAYS-PAY-#{Date.current.strftime('%Y%m%d')}" ]
      csv << [ "Payment Description", "Hotel Payouts Batch #{Date.current.to_s}" ]
      csv << [ "Bulk Payment Type", "PAYMENT" ]
      csv << [] # Row 7 empty
      
      # Row 8: Table Headers
      csv << [
        "Beneficiary Name",
        "Beneficiary Bank",
        "Beneficiary Account No",
        "ID Type",
        "ID Number",
        "Payment Amount",
        "Payment Reference",
        "Payment Description"
      ]

      # Data Rows (Aggregated by Hotel)
      bookings_to_process.group_by(&:hotel_id).each do |hotel_id, bookings|
        hotel = Hotel.find(hotel_id)
        account = hotel.account
        banking = account.banking_detail

        next unless banking # Skip if no banking details

        total_payout = bookings.sum { |b| b.net_amount || 0 }
        
        csv << [
          banking.account_holder_name,
          banking.bank_name,
          banking.account_number,
          "BUSINESS", # Assuming business for hotels
          account.slug.upcase, # Using slug as a dummy ID number if not available
          format("%.2f", total_payout),
          "WS-#{hotel.id}-#{Date.current.strftime('%m%d')}",
          "WAStays Payout for #{bookings.count} stays"
        ]
      end
    end

    send_data csv_data, filename: "Maybank_Payout_#{Date.current.to_s}.csv", type: "text/csv"
  end

  def mark_as_paid
    cutoff_date = last_friday.end_of_day
    reference = "PAY-#{SecureRandom.hex(4).upcase}"
    
    Booking.transaction do
      bookings = Booking.completed
                        .where(payout_status: "pending")
                        .where("checked_out_at <= ?", cutoff_date)
      
      bookings.update_all(
        payout_status: "paid",
        payout_at: Time.current,
        payout_reference: reference
      )
    end

    redirect_to admin_payouts_path, notice: "Selected bookings marked as paid with reference: #{reference}"
  end

  private

  def last_friday
    date = Date.current
    date -= 1 while !date.friday?
    date
  end
end
