# frozen_string_literal: true

module HotelPortal
  class PhotoQueueService
    attr_reader :session, :hotel

    def initialize(session, hotel)
      @session = session
      @hotel = hotel
    end

    def queued_photo_signed_ids
      Array(queue_session[hotel.id.to_s]).reject(&:blank?)
    end

    def queued_count
      queued_photo_signed_ids.size
    end

    def remaining_slots
      [ Hotel::MAX_PHOTOS - hotel.photos.count - queued_count, 0 ].max
    end

    def enqueue(uploaded_file)
      return { error: "Please choose at least one image." } if uploaded_file.blank?
      return { error: "Only image files are allowed." } unless uploaded_file.content_type.to_s.start_with?("image/")
      return { error: "You already reached the maximum of #{Hotel::MAX_PHOTOS} photos." } if remaining_slots <= 0

      uploaded_file.tempfile.rewind
      blob = ActiveStorage::Blob.create_and_upload!(
        io: uploaded_file.tempfile,
        filename: uploaded_file.original_filename,
        content_type: uploaded_file.content_type
      )

      signed_ids = (queued_photo_signed_ids + [ blob.signed_id ]).uniq
      write_queued_photo_signed_ids(signed_ids)
      { blob: blob }
    rescue StandardError
      { error: "Unable to queue this photo. Please try again." }
    end

    def remove(signed_id)
      signed_ids = queued_photo_signed_ids
      if signed_ids.delete(signed_id)
        write_queued_photo_signed_ids(signed_ids)
        purge_blob_by_signed_id(signed_id)
        true
      else
        false
      end
    end

    def clear
      queued_photo_signed_ids.each { |signed_id| purge_blob_by_signed_id(signed_id) }
      write_queued_photo_signed_ids([])
    end

    def commit
      queue_signed_ids = queued_photo_signed_ids
      resolved_items = queue_signed_ids.filter_map do |signed_id|
        blob = ActiveStorage::Blob.find_signed(signed_id)
        [ signed_id, blob ] if blob
      end

      queue_blobs = resolved_items.map(&:second)
      upload_result = hotel.attach_photos_with_limit(queue_blobs)

      # Purge blobs that were not attached due to limit
      trimmed_signed_ids = resolved_items.map(&:first).drop(upload_result.attached_count)
      purge_blobs_by_signed_ids(trimmed_signed_ids)

      write_queued_photo_signed_ids([])
      upload_result
    end

    private

    def queue_session
      session[:hotel_photo_queue] ||= {}
    end

    def write_queued_photo_signed_ids(signed_ids)
      queue_session[hotel.id.to_s] = signed_ids
    end

    def purge_blob_by_signed_id(signed_id)
      blob = ActiveStorage::Blob.find_signed(signed_id)
      blob&.purge if blob && !blob.attachments.exists?
    end

    def purge_blobs_by_signed_ids(signed_ids)
      signed_ids.each { |id| purge_blob_by_signed_id(id) }
    end
  end
end
