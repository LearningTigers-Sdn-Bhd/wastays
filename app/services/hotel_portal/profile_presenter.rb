# frozen_string_literal: true

module HotelPortal
  class ProfilePresenter
    include ActionView::Helpers::NumberHelper

    attr_reader :hotel, :queue_service, :context

    def initialize(hotel, queue_service, context)
      @hotel = hotel
      @queue_service = queue_service
      @context = context
    end

    def setup_fee_amount
      active_setup_fee&.amount&.to_f || 0.0
    end

    def setup_fee_currency
      active_setup_fee&.currency || SetupFeeRule::CURRENCY
    end

    def setup_fee_source
      hotel.setup_fee_source
    end

    def queued_photo_items
      queue_service.queued_photo_signed_ids.filter_map do |signed_id|
        blob = ActiveStorage::Blob.find_signed(signed_id)
        serialize_queued_blob(blob) if blob
      end
    end

    def queue_summary
      {
        queued_count: queue_service.queued_count,
        existing_count: hotel.photos.count,
        max_count: Hotel::MAX_PHOTOS,
        remaining_slots: queue_service.remaining_slots
      }
    end

    def serialize_queued_blob(blob)
      {
        signed_id: blob.signed_id,
        filename: blob.filename.to_s,
        byte_size: number_to_human_size(blob.byte_size),
        preview_url: context.url_for(blob)
      }
    end

    private

    def active_setup_fee
      @active_setup_fee ||= hotel.active_setup_fee
    end
  end
end
