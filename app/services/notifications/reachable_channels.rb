# frozen_string_literal: true

module Notifications
  # The channels a booking's guest can be reached on.
  #
  # A desk booking may carry only an email, only a phone, or neither until the
  # guest fills them in at check-in. A message queued for a channel with no
  # address would just fail on send, so that channel is left out.
  module ReachableChannels
    module_function

    def for(booking, channels)
      channels.map(&:to_s).select { |channel| reachable?(booking, channel) }
    end

    def reachable?(booking, channel)
      case channel.to_s
      when "email" then booking.guest_email.present?
      when "whatsapp" then booking.guest_phone.present?
      else true
      end
    end
  end
end
