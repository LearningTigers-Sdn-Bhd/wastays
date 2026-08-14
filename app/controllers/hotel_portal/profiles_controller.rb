# frozen_string_literal: true

module HotelPortal
  class ProfilesController < HotelPortal::SettingsBaseController
    before_action :set_hotel
    before_action :set_photo_queue

    def edit
      authorize @hotel
      prepare_profile_page
      render :edit, formats: :html if request.format.turbo_stream?
    end

    def update
      authorize @hotel

      form = HotelPortal::ProfileForm.new(@hotel, params)
      upload_result = form.save

      if upload_result
        flash[:alert] = upload_result.alert_message if upload_result.respond_to?(:trimmed?) && upload_result.trimmed?
        redirect_with_toast(edit_hotel_profile_path(@hotel), "Hotel profile updated successfully.", type: :success, status: :see_other)
      else
        prepare_profile_page
        render :edit, formats: :html, status: :unprocessable_content
      end
    end

    def destroy_photo
      authorize @hotel, :update?

      photo = @hotel.photos.attachments.find(params[:photo_id])
      clear_featured_photo_if_needed(photo.id)
      photo.purge

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              "hotel-published-photos",
              partial: "hotel_portal/profiles/published_photos",
              locals: { hotel: @hotel, return_to: params[:return_to] }
            ),
            toast_stream("Hotel photo removed successfully.", type: :success)
          ]
        end
        format.html { redirect_to photo_return_path, notice: "Hotel photo removed successfully." }
      end
    rescue ActiveRecord::RecordNotFound
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: toast_stream("Hotel photo could not be found.", type: :error), status: :not_found
        end
        format.html { redirect_to photo_return_path, alert: "Hotel photo could not be found." }
      end
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
        redirect_to photo_return_path, alert: "Hotel photo could not be found."
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
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.replace(
                "hotel-published-photos",
                partial: "hotel_portal/profiles/published_photos",
                locals: { hotel: @hotel, return_to: params[:return_to] }
              ),
              toast_stream("Featured photo updated successfully.", type: :success)
            ]
          end
          format.html { redirect_to photo_return_path, notice: "Featured photo updated successfully." }
        end
      else
        message = @hotel.errors.full_messages.to_sentence
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: toast_stream(message, type: :error), status: :unprocessable_content
          end
          format.html { redirect_to edit_hotel_profile_path(@hotel), alert: message }
        end
      end
    rescue ActiveRecord::RecordNotFound
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: toast_stream("Hotel photo could not be found.", type: :error), status: :not_found
        end
        format.html { redirect_to photo_return_path, alert: "Hotel photo could not be found." }
      end
    end

    def enqueue_photo
      authorize @hotel, :update?

      result = @photo_queue.enqueue(params[:photo])

      if result[:error]
        render json: { error: result[:error] }, status: :unprocessable_content
      else
        presenter = HotelPortal::ProfilePresenter.new(@hotel, @photo_queue, self)
        render json: {
          queue_item: presenter.serialize_queued_blob(result[:blob]),
          summary: @photo_queue.summary
        }
      end
    end

    def remove_photo_from_queue
      authorize @hotel, :update?

      if @photo_queue.remove(params[:signed_id])
        render json: { summary: @photo_queue.summary }
      else
        render json: { error: "Queued photo could not be found." }, status: :not_found
      end
    end

    def clear_photo_queue
      authorize @hotel, :update?

      @photo_queue.clear
      render json: { summary: @photo_queue.summary }
    end

    def commit_photo_queue
      authorize @hotel, :update?

      upload_result = @photo_queue.commit
      render json: {
        summary: @photo_queue.summary,
        current_photos_count: @hotel.photos.count,
        attached_count: upload_result.attached_count,
        alert: upload_result.trimmed? ? upload_result.alert_message : nil
      }
    end


    private

    def set_hotel
      @hotel = current_hotel
    end

    def set_photo_queue
      @photo_queue = HotelPortal::PhotoQueue.new(@hotel, session)
    end

    def prepare_profile_page
      @presenter = HotelPortal::ProfilePresenter.new(@hotel, @photo_queue, view_context)
    end

    def photo_return_path
      if params[:return_to] == "onboarding"
        hotel_onboarding_section_path(@hotel, section_key: "property_photos")
      else
        edit_hotel_profile_path(@hotel)
      end
    end

    # Removing the featured photo does not leave the property without one. The
    # remaining photos promote their own replacement, so "has photos" and "has a
    # featured photo" never come apart — which is what lets the photos setup step
    # ask only for a photo. Callers purge after this runs, so the promoted
    # attachment is chosen from what will still be there.
    def clear_featured_photo_if_needed(photo_ids)
      return unless @hotel.featured_photo_attachment_id.present?

      removed_ids = Array(photo_ids).map(&:to_i)
      return unless removed_ids.include?(@hotel.featured_photo_attachment_id.to_i)

      successor = @hotel.photos.attachments.where.not(id: removed_ids).order(:id).first
      @hotel.update_column(:featured_photo_attachment_id, successor&.id)
    end
  end
end
