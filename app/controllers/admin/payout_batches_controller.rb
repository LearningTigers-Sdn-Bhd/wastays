class Admin::PayoutBatchesController < Admin::BaseController
  include FinancialFiltering

  def index
    # We use period_end for date filtering batches
    @base_batches = PayoutBatch.includes(:hotel)
                               .where(period_end: @start_date..@end_date)
                               .search(params[:q])

    @active_tab = params[:tab] || "pending"

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

  def export_payouts_csv
    # Export only pending batches in the selected filter
    batches_to_process = PayoutBatch.pending
                                    .includes(hotel: [ account: :banking_detail ])
                                    .where(period_end: @start_date..@end_date)

    if batches_to_process.empty?
      redirect_to admin_payout_batches_path(date_preset: @date_preset), alert: "No pending batches to export for this period."
      return
    end

    service = PayoutExportService.new(batches_to_process, type: :batches)
    csv_data = service.generate_csv

    send_data csv_data, filename: "Payout_Batch_#{@start_date}_#{@end_date}.csv", type: "text/csv"
  end

  private

  def batch_params
    params.require(:payout_batch).permit(:receipt, :payout_reference, :payout_at)
  end
end
