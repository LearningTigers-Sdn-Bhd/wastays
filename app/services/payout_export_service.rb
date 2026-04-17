require "csv"

class PayoutExportService
  def initialize(items, type: :batches)
    @items = items
    @type = type
  end

  def generate_csv
    CSV.generate(headers: false) do |csv|
      csv << [ "Crediting Date (eg. dd/MM/yyyy)", Date.current.strftime("%d/%m/%Y") ]
      csv << [ "Payment Reference", "WASTAYS-PAY-#{Date.current.strftime('%Y%m%d')}" ]
      csv << [ "Payment Description", "Hotel Payouts Batch #{Date.current}" ]
      csv << [ "Bulk Payment Type", "PAYMENT" ]
      csv << []

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

      if @type == :batches
        process_batches(csv)
      else
        process_bookings(csv)
      end
    end
  end

  private

  def process_batches(csv)
    @items.each do |batch|
      hotel = batch.hotel
      account = hotel.account
      banking = account.banking_detail

      next unless banking

      csv << [
        banking.account_holder_name,
        banking.bank_name,
        banking.account_number,
        "BUSINESS",
        account.slug.upcase,
        format("%.2f", batch.amount),
        "BATCH-#{batch.id}",
        "WAStays Payout #{batch.period_start} to #{batch.period_end}"
      ]
    end
  end

  def process_bookings(csv)
    @items.group_by(&:hotel_id).each do |hotel_id, bookings|
      hotel = Hotel.find(hotel_id)
      account = hotel.account
      banking = account.banking_detail

      next unless banking

      total_payout = bookings.sum { |b| b.net_amount || 0 }

      csv << [
        banking.account_holder_name,
        banking.bank_name,
        banking.account_number,
        "BUSINESS",
        account.slug.upcase,
        format("%.2f", total_payout),
        "WS-#{hotel.id}-#{Date.current.strftime('%m%d')}",
        "WAStays Payout for #{bookings.count} stays"
      ]
    end
  end
end
