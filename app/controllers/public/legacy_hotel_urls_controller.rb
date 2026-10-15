class Public::LegacyHotelUrlsController < ApplicationController
  DEPLOYED_ON = Date.new(2026, 9, 15)
  SUNSET_ON = DEPLOYED_ON + 90

  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def hotel
    redirect_legacy("hotel", hotel_path(hotel_code, public_id))
  end

  def rate_calendar
    redirect_legacy("rate_calendar", rate_calendar_hotel_path(hotel_code, public_id))
  end

  def concierge
    destination = concierge_home_path(hotel_code, public_id)
    destination = File.join(destination, params[:legacy_suffix]) if params[:legacy_suffix].present?

    redirect_legacy("concierge", destination)
  end

  private

  def redirect_legacy(route_family, destination)
    return not_found if Date.current >= SUNSET_ON

    Rails.logger.info(
      "legacy_public_hotel_url_redirect " \
      "route_family=#{route_family} identifier_type=#{identifier_type} sunset_on=#{SUNSET_ON.iso8601}"
    )

    destination = "#{destination}?#{request.query_string}" if request.query_string.present?
    redirect_to destination, status: :temporary_redirect
  end

  def hotel_record
    @hotel_record ||= Hotel.locate!(params[:legacy_hotel_identifier])
  end

  def hotel_code
    hotel_record.unique_id
  end

  def public_id
    hotel_record.public_id
  end

  def identifier_type
    params[:legacy_hotel_identifier].to_s.casecmp?(hotel_code) ? "code" : "slug"
  end

  def not_found
    head :not_found
  end
end
