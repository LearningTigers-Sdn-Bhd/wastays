# frozen_string_literal: true

# Remembers which visitor a browser belongs to, so a returning guest picks the
# same thread back up instead of starting a stranger's conversation.
#
# Signed rather than plain: the public_id is the only thing standing between a
# browser and someone else's chat history, so it must not be editable by the
# person holding it. Deliberately long-lived -- a guest who asks about rooms on
# Monday and comes back on Thursday is the same enquiry.
module ConciergeChatSession
  extend ActiveSupport::Concern

  CHAT_COOKIE = :concierge_chat
  CHAT_TTL = 30.days

  def current_chat_prospect_public_id
    raw = cookies.signed[CHAT_COOKIE]
    return nil if raw.blank?

    data = JSON.parse(raw)
    return nil if data["hotel_id"].to_i != @hotel.id

    data["prospect_public_id"].presence
  rescue JSON::ParserError
    nil
  end

  def set_chat_prospect_cookie(prospect)
    cookies.signed[CHAT_COOKIE] = {
      value: { prospect_public_id: prospect.public_id, hotel_id: @hotel.id }.to_json,
      expires: CHAT_TTL.from_now,
      httponly: true,
      same_site: :lax
    }
  end
end
