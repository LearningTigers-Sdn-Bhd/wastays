# frozen_string_literal: true

# Tells a super agent when a hotel joins with their code and when it goes live.
class SuperAgentMailer < ApplicationMailer
  # A hotel registered with the agent's invite link.
  def hotel_registered(hotel)
    @hotel = hotel
    @agent = hotel.created_by_user
    @owner = hotel.user_hotel_accesses.joins(:role).find_by(roles: { slug: "hotel_owner" })&.user

    mail(to: @agent.email, subject: "#{@hotel.name} registered with your invite link")
  end

  # The hotel finished onboarding and can take bookings.
  def hotel_live(delivery)
    @hotel = delivery.onboarding_submission.hotel

    mail(to: delivery.recipient_email, subject: "#{@hotel.name} is now live")
  end
end
