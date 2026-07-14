module Admin::HotelsHelper
  def admin_hotel_form_cancel_path(hotel)
    hotel.persisted? ? admin_hotel_path(hotel) : admin_hotels_path
  end

  def categorized_hotel_amenities
    Hotel::CATEGORIZED_HOTEL_AMENITIES
  end
end
