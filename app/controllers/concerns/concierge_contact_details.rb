# The property's contacts for a guest: the front desk, its hours, and who to call
# in an emergency. The public contact page and the stay contact page read the
# same values, so the two pages cannot drift apart.
module ConciergeContactDetails
  private

  def load_contact_details
    @policy = @hotel.property_policy
    @guest_contact = @hotel.guest_contact
    @front_desk_status = ::Concierge::FrontDeskStatusPresenter.new(hotel: @hotel)
    @phone = contact_value(:front_desk_phone, @hotel.contact_phone)
    @email = contact_value(:front_desk_email, @hotel.contact_email)
    @whatsapp_number = contact_value(:front_desk_whatsapp, @hotel.whatsapp_number)
    @whatsapp_link = whatsapp_link
    @maps_link = maps_link
  end

  # The Contact and Escalation page wins where staff filled it. The hotel
  # record stays the fallback, so a property that never opened that page
  # keeps the contacts it already had.
  def contact_value(attribute, fallback)
    @guest_contact&.public_send(attribute).presence || fallback.presence
  end

  def whatsapp_link
    number = @whatsapp_number.presence || @phone.presence
    return nil unless number
    digits = number.gsub(/\D/, "")
    "https://wa.me/#{digits}"
  end

  def maps_link
    query = [ @hotel.address, @hotel.city, @hotel.country ].compact_blank.join(", ")
    return nil if query.blank?
    "https://www.google.com/maps/search/?api=1&query=#{CGI.escape(query)}"
  end
end
