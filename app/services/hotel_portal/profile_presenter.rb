# frozen_string_literal: true

module HotelPortal
  class ProfilePresenter
    include ActionView::Helpers::NumberHelper

    attr_reader :hotel, :photo_queue, :context

    def initialize(hotel, photo_queue, context)
      @hotel = hotel
      @photo_queue = photo_queue
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
      photo_queue.items.map do |blob|
        serialize_queued_blob(blob)
      end
    end

    def queue_summary
      photo_queue.summary
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
