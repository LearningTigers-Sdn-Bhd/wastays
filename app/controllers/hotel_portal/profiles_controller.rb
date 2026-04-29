# frozen_string_literal: true

module HotelPortal
  class ProfilesController < HotelPortal::BaseController
    before_action :set_hotel, only: %i[edit update destroy_photo destroy_photos set_featured_photo enqueue_photo remove_photo_from_queue clear_photo_queue commit_photo_queue]

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

      result = photo_queue.enqueue(uploaded_file)

      if result[:success]
        render json: {
          queue_item: serialize_queued_blob(result[:blob]),
          summary: photo_queue.summary
        }
      else
        render json: { error: result[:error] }, status: :unprocessable_content
      end
    rescue StandardError => e
      Rails.logger.error "Photo queue error: #{e.message}\n#{e.backtrace.join("\n")}"
      render json: { error: "Unable to queue this photo. Please try again." }, status: :unprocessable_content
    end

    def remove_photo_from_queue
      authorize @hotel, :update?

      if photo_queue.remove(params[:signed_id])
        render json: { summary: photo_queue.summary }
      else
        render json: { error: "Queued photo could not be found." }, status: :not_found
      end
    end

    def clear_photo_queue
      authorize @hotel, :update?
      photo_queue.clear
      render json: { summary: photo_queue.summary }
    end

    def commit_photo_queue
      authorize @hotel, :update?

      upload_result = photo_queue.commit
      alert_message = upload_result.trimmed? ? upload_result.alert_message : nil

      render json: {
        summary: photo_queue.summary,
        current_photos_count: @hotel.photos.count,
        attached_count: upload_result.attached_count,
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

    def photo_queue
      @photo_queue ||= HotelPortal::PhotoQueue.new(@hotel, session)
    end

    def clear_featured_photo_if_needed(photo_ids)
      return unless @hotel.featured_photo_attachment_id.present?
      return unless Array(photo_ids).map(&:to_i).include?(@hotel.featured_photo_attachment_id.to_i)

      @hotel.update_column(:featured_photo_attachment_id, nil)
    end

    def load_setup_fee_context
      active_setup_fee = @hotel.active_setup_fee

      @setup_fee_amount = active_setup_fee&.amount&.to_f || 0.0
      @setup_fee_currency = active_setup_fee&.currency || SetupFeeRule::CURRENCY
      @setup_fee_source = @hotel.setup_fee_source
    end

    def load_queued_photo_items
      @queued_photo_items = photo_queue.items.map { |blob| serialize_queued_blob(blob) }
    end

    def serialize_queued_blob(blob)
      {
        signed_id: blob.signed_id,
        filename: blob.filename.to_s,
        byte_size: helpers.number_to_human_size(blob.byte_size),
        preview_url: url_for(blob)
      }
    end
  end
end
