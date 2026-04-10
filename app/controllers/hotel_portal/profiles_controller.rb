class HotelPortal::ProfilesController < HotelPortal::BaseController
  def edit
    @hotel = current_hotel
    authorize @hotel
  end

  def update
    @hotel = current_hotel
    authorize @hotel

    photo_files = Array(params.dig(:hotel, :photos)).reject(&:blank?)
    hotel_attributes = hotel_params.except(:photos)
    remaining_slots = [ 20 - @hotel.photos.count, 0 ].max
    photos_to_attach = photo_files.first(remaining_slots)
    trimmed_count = photo_files.size - photos_to_attach.size

    if @hotel.update(hotel_attributes)
      @hotel.photos.attach(photos_to_attach) if photos_to_attach.any?
      @hotel.complete_profile!
      if trimmed_count.positive?
        flash[:alert] = if photos_to_attach.any?
          "Only the first #{photos_to_attach.size} photo#{photos_to_attach.size == 1 ? '' : 's'} were uploaded. Extra files were ignored."
        else
          "This hotel already has 20 photos. Remove some before uploading more."
        end
      end
      redirect_to hotel_dashboard_path(@hotel), notice: "Hotel profile updated successfully."
    else
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
end
