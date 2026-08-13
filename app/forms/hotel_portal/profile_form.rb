# frozen_string_literal: true

module HotelPortal
  class ProfileForm
    include ActiveModel::Model

    attr_reader :hotel, :params

    def initialize(hotel, params = {})
      @hotel = hotel
      @params = params
    end

    def save
      profile_params = hotel_params
      profile_params[:amenities] = Array(profile_params[:amenities]).reject(&:blank?) if profile_params[:amenities]

      if hotel.update(profile_params.except(:photos))
        if (hotel.saved_changes.keys & %w[name city country amenities]).any?
          if hotel.preferred_channel_manager.present? && hotel.channel_mapping.present?
            ChannelManagers::SyncStructureJob.perform_later("Hotel", hotel.id, "sync")
          end
        end

        hotel.attach_photos_with_limit(profile_params[:photos])
      else
        false
      end
    end

    private

    def hotel_params
      permitted = params.require(:hotel).permit(
        :name, :description, :address, :city, :country, :star_rating,
        :featured_photo_attachment_id, :google_map_link, :contact_email,
        :contact_phone, :whatsapp_number, :time_zone, :default_currency,
        :tin, :ssm_number,
        photos: [], amenities: []
      )

      permitted
    end
  end
end
