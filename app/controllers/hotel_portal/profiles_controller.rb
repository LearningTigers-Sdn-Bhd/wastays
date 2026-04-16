class HotelPortal::ProfilesController < HotelPortal::BaseController
  def edit
    @hotel = current_hotel
    authorize @hotel
    load_setup_fee_context
  end

  def update
    @hotel = current_hotel
    authorize @hotel

    profile_params = hotel_params

    if @hotel.update(profile_params.except(:photos))
      photo_upload_result = @hotel.attach_photos_with_limit(profile_params[:photos])
      @hotel.complete_profile!
      flash[:alert] = photo_upload_result.alert_message if photo_upload_result.trimmed?
      redirect_to hotel_dashboard_path(@hotel), notice: "Hotel profile updated successfully."
    else
      load_setup_fee_context
      render :edit, status: :unprocessable_content
    end
  end

  def destroy_photo
    @hotel = current_hotel
    authorize @hotel, :update?

    photo = @hotel.photos.attachments.find(params[:photo_id])
    clear_featured_photo_if_needed(photo.id)
    photo.purge

    redirect_to edit_hotel_profile_path(@hotel), notice: "Hotel photo removed successfully."
  rescue ActiveRecord::RecordNotFound
    redirect_to edit_hotel_profile_path(@hotel), alert: "Hotel photo could not be found."
  end

  def destroy_photos
    @hotel = current_hotel
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
    @hotel = current_hotel
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

  private

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
end
