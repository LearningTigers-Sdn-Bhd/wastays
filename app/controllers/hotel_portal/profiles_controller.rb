# frozen_string_literal: true

module HotelPortal
  class ProfilesController < HotelPortal::SettingsBaseController
    before_action :set_hotel
    before_action :set_photo_queue

    def edit
      authorize @hotel
      prepare_profile_page
    end

    def update
      authorize @hotel

      form = HotelPortal::ProfileForm.new(@hotel, params)
      upload_result = form.save

      if upload_result
        flash[:alert] = upload_result.alert_message if upload_result.respond_to?(:trimmed?) && upload_result.trimmed?
        redirect_to edit_hotel_profile_path(@hotel), notice: "Hotel profile updated successfully."
      else
        prepare_profile_page
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

    def clear_featured_photo_if_needed(photo_ids)
      return unless @hotel.featured_photo_attachment_id.present?
      return unless Array(photo_ids).map(&:to_i).include?(@hotel.featured_photo_attachment_id.to_i)

      @hotel.update_column(:featured_photo_attachment_id, nil)
    end
  end
end
