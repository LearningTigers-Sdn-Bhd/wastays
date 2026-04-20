class HotelPortal::RefundRequestsController < HotelPortal::BaseController
  before_action :set_refund_request, only: [ :show, :approve, :reject, :complete ]

  def index
    @refund_requests = RefundRequest
      .joins(:booking)
      .where(bookings: { hotel_id: current_hotel.id })
      .order(created_at: :desc)

    @refund_status_counts = @refund_requests.except(:order).group(:status).count
    @pending_count = @refund_status_counts.fetch("pending", 0)
    @approved_count = @refund_status_counts.fetch("approved", 0)
    @completed_count = @refund_status_counts.fetch("completed", 0)
    @rejected_count = @refund_status_counts.fetch("rejected", 0)
    @total_refunds = @refund_requests.size
  end

  def show; end

  def approve
    @refund_request.update!(status: "approved", hotel_note: params[:hotel_note].presence)
    redirect_to hotel_refund_request_path(current_hotel, @refund_request), notice: "Refund request approved."
  end

  def reject
    @refund_request.update!(status: "rejected", hotel_note: params[:hotel_note].presence)
    redirect_to hotel_refund_request_path(current_hotel, @refund_request), notice: "Refund request rejected."
  end

  def complete
    @refund_request.update!(status: "completed")
    RefundMailer.completed(@refund_request).deliver_later
    redirect_to hotel_refund_request_path(current_hotel, @refund_request), notice: "Refund marked as completed. Guest has been notified."
  end

  private

  def set_refund_request
    @refund_request = RefundRequest
      .joins(:booking)
      .where(bookings: { hotel_id: current_hotel.id })
      .find(params[:id])
  end
end
