require "csv"

class Admin::PayoutBatchesController < Admin::BaseController
  include FinancialFiltering

  def index
    # We use period_end for date filtering batches
    @base_batches = PayoutBatch.includes(:hotel)
                               .where(period_end: @start_date..@end_date)
    
    @active_tab = params[:tab] || "pending"

    if params[:q].present?
      @base_batches = @base_batches.joins(:hotel).where(
        "hotels.name ILIKE :q OR payout_reference ILIKE :q", 
        q: "%#{params[:q]}%"
      )
    end

    @pending_batches = @base_batches.pending.page(params[:pending_page]).per(25)
    @paid_batches = @base_batches.paid.order(payout_at: :desc).page(params[:paid_page]).per(25)
  end

  def show
    @batch = PayoutBatch.find(params[:id])
    @bookings = @batch.bookings.order(checked_out_at: :asc)
  end

  def update
    @batch = PayoutBatch.find(params[:id])
    if @batch.update(batch_params)
      redirect_to admin_payout_batch_path(@batch), notice: "Batch updated successfully."
    else
      render :show, alert: "Failed to update batch."
    end
  end

  def mark_as_paid
    @batch = PayoutBatch.find(params[:id])
    
    PayoutBatch.transaction do
      @batch.update!(
        status: "paid",
        payout_at: Time.current,
        payout_reference: params[:payout_reference] || "PAY-#{SecureRandom.hex(4).upcase}"
      )
      @batch.bookings.update_all(payout_status: "paid", payout_at: Time.current)
    end

    redirect_to admin_payout_batch_path(@batch), notice: "Batch marked as paid."
  end

  def export_maybank
    # Export only pending batches in the selected filter
    batches_to_process = PayoutBatch.pending
                                    .includes(hotel: [ account: :banking_detail ])
                                    .where(period_end: @start_date..@end_date)

    if batches_to_process.empty?
      redirect_to admin_payout_batches_path(date_preset: @date_preset), alert: "No pending batches to export for this period."
      return
    end

    csv_data = CSV.generate(headers: false) do |csv|
      csv << [ "Crediting Date (eg. dd/MM/yyyy)", Date.current.strftime("%d/%m/%Y") ]
      csv << [ "Payment Reference", "WASTAYS-BATCH-#{Date.current.strftime('%Y%m%d')}" ]
      csv << [ "Payment Description", "Hotel Payouts Batch #{Date.current.to_s}" ]
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

      batches_to_process.each do |batch|
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

    send_data csv_data, filename: "Maybank_Payout_Batch_#{@start_date}_#{@end_date}.csv", type: "text/csv"
  end

  private

  def batch_params
    params.require(:payout_batch).permit(:receipt, :payout_reference, :payout_at)
  end
end
