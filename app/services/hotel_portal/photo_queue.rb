# frozen_string_literal: true

module HotelPortal
  class PhotoQueue
    attr_reader :hotel, :session

    def initialize(hotel, session)
      @hotel = hotel
      @session = session
    end

    def enqueue(uploaded_file)
      return { error: "Only image files are allowed." } unless uploaded_file.content_type.to_s.start_with?("image/")
      return { error: "You already reached the maximum of #{Hotel::MAX_PHOTOS} photos." } if remaining_slots <= 0

      blob = ActiveStorage::Blob.create_and_upload!(
        io: uploaded_file,
        filename: uploaded_file.original_filename,
        content_type: uploaded_file.content_type
      )

      add_to_session(blob.id)
      { success: true, blob: blob }
    end

    def remove(signed_id)
      blob_id = resolve_blob_id(signed_id)
      return false unless blob_id
      return false unless blob_ids.delete(blob_id)

      persist_session(blob_ids)
      purge_blob(signed_id)
      true
    end

    def clear
      blob_ids.each { |blob_id| purge_blob(blob_id) }
      persist_session([])
    end

    def commit
      ids = blob_ids
      resolved_items = ids.filter_map do |blob_id|
        blob = ActiveStorage::Blob.find_by(id: blob_id)
        [ blob_id, blob ] if blob
      end

      blobs = resolved_items.map(&:second)
      upload_result = hotel.attach_photos_with_limit(blobs)

      attached_count = upload_result.attached_count
      trimmed_ids = resolved_items.map(&:first).drop(attached_count)

      purge_blobs(trimmed_ids)
      persist_session([])

      upload_result
    end

    def items
      blob_ids.filter_map do |blob_id|
        ActiveStorage::Blob.find_by(id: blob_id)
      end
    end

    def summary
      {
        queued_count: blob_ids.size,
        existing_count: hotel.photos.count,
        max_count: Hotel::MAX_PHOTOS,
        remaining_slots: remaining_slots
      }
    end

    def remaining_slots
      [ Hotel::MAX_PHOTOS - hotel.photos.count - blob_ids.size, 0 ].max
    end

    private

    def blob_ids
      @blob_ids ||= begin
        values = Array(queue_session[hotel.id.to_s]).reject(&:blank?)

        values.filter_map do |value|
          if value.to_s.match?(/\A\d+\z/)
            value.to_i
          else
            ActiveStorage::Blob.find_signed(value)&.id
          end
        end.uniq
      end
    end

    def queue_session
      session[:hotel_photo_queue] ||= {}
    end

    def add_to_session(blob_id)
      new_ids = (blob_ids + [ blob_id ]).uniq
      persist_session(new_ids)
    end

    def persist_session(new_ids)
      session[:hotel_photo_queue] = queue_session.merge(hotel.id.to_s => new_ids)
      @blob_ids = new_ids
    end

    def resolve_blob_id(identifier)
      return if identifier.blank?
      return identifier.to_i if identifier.to_s.match?(/\A\d+\z/)

      ActiveStorage::Blob.find_signed(identifier)&.id
    end

    def purge_blob(identifier)
      blob_id = resolve_blob_id(identifier)
      return unless blob_id

      blob = ActiveStorage::Blob.find_by(id: blob_id)
      blob&.purge if blob && !blob.attachments.exists?
    end

    def purge_blobs(ids)
      ids.each { |id| purge_blob(id) }
    end
  end
end
