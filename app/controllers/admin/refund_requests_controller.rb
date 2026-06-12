module Admin
  class RefundRequestsController < Admin::BaseController
    before_action :set_refund_request, only: [ :show, :approve, :reject, :complete ]
    before_action :set_breadcrumbs, only: [ :show ]

    def index
      @all_refund_requests = RefundRequest.includes(booking: :hotel).order(created_at: :desc)
      @refund_requests = @all_refund_requests.page(params[:page]).per(25)

      @refund_status_counts = @all_refund_requests.except(:order).group(:status).count
      @pending_count   = @refund_status_counts.fetch("pending", 0)
      @approved_count  = @refund_status_counts.fetch("approved", 0)
      @completed_count = @refund_status_counts.fetch("completed", 0)
      @rejected_count  = @refund_status_counts.fetch("rejected", 0)
      @total_refunds   = @all_refund_requests.size
    end

    def show; end

    def approve
      @refund_request.update!(status: "approved", hotel_note: params[:hotel_note].presence)
      redirect_to admin_refund_request_path(@refund_request), notice: "Refund request approved."
    end

    def reject
      @refund_request.update!(status: "rejected", hotel_note: params[:hotel_note].presence)
      redirect_to admin_refund_request_path(@refund_request), notice: "Refund request rejected."
    end

    def complete
      ActiveRecord::Base.transaction do
        folio_result = Folios::RecordRefund.call(refund_request: @refund_request, user: current_user)
        raise "Failed to record refund in folio: #{folio_result.error}" unless folio_result.success?

        @refund_request.update!(status: "completed")
        @refund_request.booking.update!(payment_status: "refunded")
        Bookings::RecordAuditLog.call!(
          auditable: @refund_request.booking,
          user: current_user,
          action_type: "refund_completed",
          source: "staff",
          metadata: { "refund_request_id" => @refund_request.id }
        )
      end
      RefundMailer.completed(@refund_request).deliver_later
      redirect_to admin_refund_request_path(@refund_request), notice: "Refund marked as completed. Guest has been notified."
    end

    private

    def set_refund_request
      @refund_request = RefundRequest.includes(booking: :hotel).find(params[:id])
    end

    def set_breadcrumbs
      append_breadcrumb @refund_request.booking.confirmation_token, admin_refund_request_path(@refund_request)
    end
  end
end
