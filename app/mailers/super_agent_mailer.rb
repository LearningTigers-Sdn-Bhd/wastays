# frozen_string_literal: true

# Keeps a super agent informed about the hotels linked to them.
class SuperAgentMailer < ApplicationMailer
  # Subject ending, status and next step for each onboarding step.
  UPDATES = {
    "agent_submitted" => {
      subject: "setup submitted for review",
      status: "Submitted for review",
      next_step: "WAStays checks the setup. You get an email when it is approved or needs changes."
    },
    "agent_changes_requested" => {
      subject: "changes requested",
      status: "Changes requested",
      next_step: "The owner must fix the setup and submit again. Open the hotel to help."
    },
    "agent_launch_decision_required" => {
      subject: "approved, waiting for launch",
      status: "Approved",
      next_step: "The owner must choose when to launch."
    },
    "agent_approved" => {
      subject: "now live",
      status: "Live",
      next_step: "The hotel can take bookings now."
    }
  }.freeze

  # A hotel registered with the agent's invite link.
  def hotel_registered(hotel)
    @hotel = hotel
    @agent = hotel.created_by_user
    @owner = hotel.user_hotel_accesses.joins(:role).find_by(roles: { slug: "hotel_owner" })&.user

    mail(to: @agent.email, subject: "#{@hotel.name} registered with your invite link")
  end

  def onboarding_update(delivery)
    @hotel = delivery.onboarding_submission.hotel
    @update = UPDATES.fetch(delivery.delivery_type)

    mail(to: delivery.recipient_email, subject: "#{@hotel.name}: #{@update[:subject]}")
  end
end
