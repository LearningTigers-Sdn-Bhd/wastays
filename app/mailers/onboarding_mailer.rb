# frozen_string_literal: true

class OnboardingMailer < ApplicationMailer
  def submitted(delivery)
    prepare(delivery)
    mail(to: delivery.recipient_email, subject: "#{@hotel.name} submitted setup for review")
  end

  def changes_requested(delivery)
    prepare(delivery)
    mail(to: delivery.recipient_email, subject: "WAStays requested changes to #{@hotel.name}")
  end

  def approved(delivery)
    prepare(delivery)
    mail(to: delivery.recipient_email, subject: "#{@hotel.name} is now live on WAStays")
  end

  private

  def prepare(delivery)
    @delivery = delivery
    @submission = delivery.onboarding_submission
    @hotel = @submission.hotel
  end
end
