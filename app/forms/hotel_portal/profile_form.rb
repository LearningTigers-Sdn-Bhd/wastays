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
      photos = profile_params.delete(:photos)
      remove_icon = ActiveModel::Type::Boolean.new.cast(profile_params.delete(:remove_icon))
      replacing_icon = profile_params[:icon].present?

      if hotel.update(profile_params)
        if (hotel.saved_changes.keys & %w[name city country amenities]).any?
          if hotel.preferred_channel_manager.present? && hotel.channel_mapping.present?
            ChannelManagers::SyncStructureJob.perform_later("Hotel", hotel.id, "sync")
          end
        end

        hotel.icon.purge_later if remove_icon && !replacing_icon
        hotel.attach_photos_with_limit(photos)
      else
        false
      end
    end

    private

    def hotel_params
      permitted = params.require(:hotel).permit(
        :name, :description, :address, :city, :country, :star_rating,
        :featured_photo_attachment_id, :google_map_link, :contact_email,
        :contact_phone, :fixed_line_number, :whatsapp_number, :time_zone, :default_currency,
        :tin, :ssm_number, :local_government_name, :local_government_license_number,
        :icon, :remove_icon, photos: [], amenities: []
      )

      permitted
    end
  end
end
