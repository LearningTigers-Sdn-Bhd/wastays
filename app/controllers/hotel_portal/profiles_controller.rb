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

    if photo_upload_limit_exceeded?(photo_files)
      @hotel.assign_attributes(hotel_attributes)
      @hotel.errors.add(:photos, "cannot exceed 20 photos")
      render :edit, status: :unprocessable_content
      return
    end

    if @hotel.update(hotel_attributes)
      @hotel.photos.attach(photo_files) if photo_files.any?
      @hotel.complete_profile!
      redirect_to edit_hotel_profile_path, notice: "Hotel profile updated successfully."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy_photo
    @hotel = current_hotel
    authorize @hotel, :update?

    photo = @hotel.photos.attachments.find(params[:photo_id])
    photo.purge

    redirect_to edit_hotel_profile_path, notice: "Hotel photo removed successfully."
  rescue ActiveRecord::RecordNotFound
    redirect_to edit_hotel_profile_path, alert: "Hotel photo could not be found."
  end

  def destroy_photos
    @hotel = current_hotel
    authorize @hotel, :update?

    photo_ids = Array(params[:photo_ids]).reject(&:blank?)

    if photo_ids.empty?
      redirect_to edit_hotel_profile_path, alert: "Please select at least one photo to remove."
      return
    end

    photos = @hotel.photos.attachments.where(id: photo_ids)

    if photos.empty?
      redirect_to edit_hotel_profile_path, alert: "Hotel photo could not be found."
      return
    end

    photos.each(&:purge)

    redirect_to edit_hotel_profile_path, notice: "Selected hotel photos removed successfully."
  end

  private

  def hotel_params
    params.require(:hotel).permit(:name, :address, :city, :country, :star_rating, photos: [])
  end

  def photo_upload_limit_exceeded?(photo_files)
    photo_files.size + @hotel.photos.count > 20
  end
end
