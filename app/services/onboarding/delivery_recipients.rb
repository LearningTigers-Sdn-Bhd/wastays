# frozen_string_literal: true

module Onboarding
  class DeliveryRecipients
    def self.admins_for(hotel)
      recipients = User.where(role: "superadmin").pluck(:email)
      recipients << hotel.salesperson.email if hotel.salesperson&.email.present? && !hotel.salesperson.email.end_with?(".local")
      recipients.compact_blank.map(&:downcase).uniq
    end

    # The super agent linked to the hotel, if any.
    def self.agent_for(hotel)
      agent = hotel.created_by_user
      agent.email.downcase if agent&.super_agent? && agent.email.present?
    end

    def self.owners_for(hotel)
      hotel.user_hotel_accesses.active.joins(:role, :user)
           .where(roles: { slug: "hotel_owner" }).pluck("users.email")
           .compact_blank.map(&:downcase).uniq
    end
  end
end
