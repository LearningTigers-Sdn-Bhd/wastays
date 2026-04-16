class HotelPortal::RequestsController < HotelPortal::BaseController
  def index
    @board = ::HotelPortal::RequestsBoard.new(current_hotel)
    @board_columns = @board.board_columns
    @board_counts = @board.board_counts
  end

  def archive
    archive_params = params.to_unsafe_h.merge("archived" => "archived")
    @archive = ::HotelPortal::RequestsArchive.new(current_hotel, archive_params)
    @archive_rows = @archive.rows
    @archive_counts = @archive.summary_counts
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

  def archive_request
    updater = ::HotelPortal::Requests::ArchiveUpdater.new(
      hotel: current_hotel,
      kind: params[:kind],
      request_id: params[:request_id]
    )

    if (request = updater.archive)
      respond_to do |format|
        format.html { redirect_to hotel_requests_path(current_hotel), notice: "Request archived successfully." }
        format.json { render json: { ok: true, archived_at: request.archived_at } }
      end
    else
      respond_to do |format|
        format.html { redirect_to hotel_requests_path(current_hotel), alert: "Failed to archive request." }
        format.json { render json: { ok: false }, status: :unprocessable_entity }
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_to hotel_requests_path(current_hotel), alert: "Request not found." }
      format.json { render json: { ok: false }, status: :not_found }
    end
  end

  def unarchive_request
    updater = ::HotelPortal::Requests::ArchiveUpdater.new(
      hotel: current_hotel,
      kind: params[:kind],
      request_id: params[:request_id]
    )

    if (request = updater.unarchive)
      respond_to do |format|
        format.html { redirect_to hotel_request_archive_path(current_hotel), notice: "Request restored successfully." }
        format.json { render json: { ok: true, archived_at: request.archived_at } }
      end
    else
      respond_to do |format|
        format.html { redirect_to hotel_request_archive_path(current_hotel), alert: "Failed to restore request." }
        format.json { render json: { ok: false }, status: :unprocessable_entity }
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_to hotel_request_archive_path(current_hotel), alert: "Request not found." }
      format.json { render json: { ok: false }, status: :not_found }
    end
  end
end
