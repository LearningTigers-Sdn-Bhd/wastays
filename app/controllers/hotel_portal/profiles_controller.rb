class HotelPortal::ProfilesController < HotelPortal::BaseController
  before_action :set_hotel, only: [ :edit, :update, :destroy_photo, :destroy_photos, :set_featured_photo, :enqueue_photo, :remove_photo_from_queue, :clear_photo_queue, :commit_photo_queue ]

  def edit
    authorize @hotel
    load_setup_fee_context
    load_queued_photo_items
  end

  def update
    authorize @hotel

    profile_params = hotel_params

    if @hotel.update(profile_params.except(:photos))
      photo_upload_result = @hotel.attach_photos_with_limit(profile_params[:photos])
      @hotel.complete_profile!
      flash[:alert] = photo_upload_result.alert_message if photo_upload_result.trimmed?
      redirect_to hotel_dashboard_path(@hotel), notice: "Hotel profile updated successfully."
    else
      load_setup_fee_context
      load_queued_photo_items
      render :edit, status: :unprocessable_content
    end
  end

  def destroy_photo
    authorize @hotel, :update?

    photo = @hotel.photos.attachments.find(params[:photo_id])
    clear_featured_photo_if_needed(photo.id)
    photo.purge

    redirect_to edit_hotel_profile_path(@hotel), notice: "Hotel photo removed successfully."
  rescue ActiveRecord::RecordNotFound
    redirect_to edit_hotel_profile_path(@hotel), alert: "Hotel photo could not be found."
  end

  def destroy_photos
    authorize @hotel, :update?

    photo_ids = Array(params[:photo_ids]).reject(&:blank?)

    if photo_ids.empty?
      redirect_to edit_hotel_profile_path(@hotel), alert: "Please select at least one photo to remove."
      return
    end

    photos = @hotel.photos.attachments.where(id: photo_ids)

    if photos.empty?
      redirect_to edit_hotel_profile_path(@hotel), alert: "Hotel photo could not be found."
      return
    end

    clear_featured_photo_if_needed(photos.pluck(:id))
    photos.each(&:purge)

    redirect_to edit_hotel_profile_path(@hotel), notice: "Selected hotel photos removed successfully."
  end

  def set_featured_photo
    authorize @hotel, :update?

    photo = @hotel.photos.attachments.find(params[:photo_id])

    if @hotel.update(featured_photo_attachment_id: photo.id)
      redirect_to edit_hotel_profile_path(@hotel), notice: "Featured photo updated successfully."
    else
      redirect_to edit_hotel_profile_path(@hotel), alert: @hotel.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to edit_hotel_profile_path(@hotel), alert: "Hotel photo could not be found."
  end

  def enqueue_photo
    authorize @hotel, :update?

    uploaded_file = params[:photo]

    if uploaded_file.blank?
      render json: { error: "Please choose at least one image." }, status: :unprocessable_content
      return
    end

    unless uploaded_file.content_type.to_s.start_with?("image/")
      render json: { error: "Only image files are allowed." }, status: :unprocessable_content
      return
    end

    if remaining_photo_slots <= 0
      render json: { error: "You already reached the maximum of #{Hotel::MAX_PHOTOS} photos." }, status: :unprocessable_content
      return
    end

    uploaded_file.tempfile.rewind
    blob = ActiveStorage::Blob.create_and_upload!(
      io: uploaded_file.tempfile,
      filename: uploaded_file.original_filename,
      content_type: uploaded_file.content_type
    )

    queue_signed_ids = queued_photo_signed_ids
    queue_signed_ids << blob.signed_id
    write_queued_photo_signed_ids(queue_signed_ids.uniq)

    render json: { queue_item: serialize_queued_blob(blob), summary: queue_summary }
  rescue StandardError
    render json: { error: "Unable to queue this photo. Please try again." }, status: :unprocessable_content
  end

  def remove_photo_from_queue
    authorize @hotel, :update?

    signed_id = params[:signed_id].to_s
    queue_signed_ids = queued_photo_signed_ids

    unless queue_signed_ids.delete(signed_id)
      render json: { error: "Queued photo could not be found." }, status: :not_found
      return
    end

    write_queued_photo_signed_ids(queue_signed_ids)
    purge_blob_by_signed_id(signed_id)

    render json: { summary: queue_summary }
  end

  def clear_photo_queue
    authorize @hotel, :update?

    queued_photo_signed_ids.each { |signed_id| purge_blob_by_signed_id(signed_id) }
    write_queued_photo_signed_ids([])

    render json: { summary: queue_summary }
  end

  def commit_photo_queue
    authorize @hotel, :update?

    queue_signed_ids = queued_photo_signed_ids
    resolved_queue_items = queue_signed_ids.filter_map do |signed_id|
      blob = ActiveStorage::Blob.find_signed(signed_id)
      [ signed_id, blob ] if blob
    end
    queue_blobs = resolved_queue_items.map(&:second)
    upload_result = @hotel.attach_photos_with_limit(queue_blobs)
    attached_count = upload_result.attached_count
    trimmed_signed_ids = resolved_queue_items.map(&:first).drop(attached_count)

    purge_blobs_by_signed_ids(trimmed_signed_ids)
    write_queued_photo_signed_ids([])

    alert_message = upload_result.trimmed? ? upload_result.alert_message : nil

    render json: {
      summary: queue_summary,
      current_photos_count: @hotel.photos.count,
      attached_count: attached_count,
      alert: alert_message
    }
  end

  private

  def set_hotel
    @hotel = current_hotel
  end

  def hotel_params
    params.require(:hotel).permit(:name, :address, :city, :country, :star_rating, :featured_photo_attachment_id, photos: [])
  end

  def clear_featured_photo_if_needed(photo_ids)
    return unless @hotel.featured_photo_attachment_id.present?
    return unless Array(photo_ids).map(&:to_i).include?(@hotel.featured_photo_attachment_id.to_i)

    @hotel.update_column(:featured_photo_attachment_id, nil)
  end

  def load_setup_fee_context
    setup_fee_override = SetupFeeRule.active.find_by(settable: @hotel)
    setup_fee_default = SetupFeeRule.active.where(settable_id: nil).find_by(settable_type: [ nil, "" ])
    active_setup_fee = setup_fee_override || setup_fee_default

    @setup_fee_amount = active_setup_fee&.amount&.to_f || 0.0
    @setup_fee_currency = active_setup_fee&.currency || SetupFeeRule::CURRENCY
    @setup_fee_source =
      if setup_fee_override
        "Hotel Override"
      elsif setup_fee_default
        "Global Default"
      else
        "Not Configured"
      end
  end

  def load_queued_photo_items
    @queued_photo_items = queued_photo_signed_ids.filter_map do |signed_id|
      blob = ActiveStorage::Blob.find_signed(signed_id)
      serialize_queued_blob(blob) if blob
    end
  end

  def queue_summary
    {
      queued_count: queued_photo_signed_ids.size,
      existing_count: @hotel.photos.count,
      max_count: Hotel::MAX_PHOTOS,
      remaining_slots: remaining_photo_slots
    }
  end

  def remaining_photo_slots
    [ Hotel::MAX_PHOTOS - @hotel.photos.count - queued_photo_signed_ids.size, 0 ].max
  end

  def queue_session
    session[:hotel_photo_queue] ||= {}
  end

  def queued_photo_signed_ids
    Array(queue_session[@hotel.id.to_s]).reject(&:blank?)
  end

  def write_queued_photo_signed_ids(signed_ids)
    queue_session[@hotel.id.to_s] = signed_ids
  end

  def serialize_queued_blob(blob)
    {
      signed_id: blob.signed_id,
      filename: blob.filename.to_s,
      byte_size: helpers.number_to_human_size(blob.byte_size),
      preview_url: url_for(blob)
    }
  end

  def purge_blob_by_signed_id(signed_id)
    blob = ActiveStorage::Blob.find_signed(signed_id)
    blob&.purge if blob && !blob.attachments.exists?
  end

  def purge_blobs_by_signed_ids(signed_ids)
    signed_ids.each { |signed_id| purge_blob_by_signed_id(signed_id) }
  end
end
