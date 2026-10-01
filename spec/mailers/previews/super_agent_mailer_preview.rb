# Preview all emails at http://localhost:3000/rails/mailers/super_agent_mailer
# Both previews use the last hotel linked to a super agent in the database.
class SuperAgentMailerPreview < ActionMailer::Preview
  def hotel_registered
    SuperAgentMailer.hotel_registered(agent_hotel)
  end

  def hotel_live
    submission = OnboardingSubmission.new(hotel: agent_hotel)
    delivery = OnboardingDelivery.new(
      onboarding_submission: submission,
      delivery_type: "agent_approved",
      recipient_email: agent_hotel.created_by_user.email
    )
    SuperAgentMailer.hotel_live(delivery)
  end

  private

  def agent_hotel
    @agent_hotel ||= Hotel.joins(:created_by_user).where(users: { role: "super_agent" }).order(:created_at).last!
  end
end
