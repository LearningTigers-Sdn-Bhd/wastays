class HotelPortal::RequestsController < HotelPortal::BaseController
  def index
    @board = ::HotelPortal::RequestsBoard.new(current_hotel)
    @board_columns = @board.board_columns
    @board_counts = @board.board_counts
  end

  def update_status
    updater = ::HotelPortal::Requests::StatusUpdater.new(
      hotel: current_hotel,
      kind: params[:kind],
      request_id: params[:request_id],
      status: params[:status]
    )

    if (request = updater.call)
      respond_to do |format|
        format.html { redirect_to hotel_requests_path(current_hotel), notice: "Request updated successfully." }
        format.json { render json: { ok: true, status: request.status } }
      end
    else
      respond_to do |format|
        format.html { redirect_to hotel_requests_path(current_hotel), alert: "Failed to update request." }
        format.json { render json: { ok: false }, status: :unprocessable_entity }
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_to hotel_requests_path(current_hotel), alert: "Request not found." }
      format.json { render json: { ok: false }, status: :not_found }
    end
  end
end
