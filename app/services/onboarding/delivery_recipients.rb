# frozen_string_literal: true

module Onboarding
  class DeliveryRecipients
    def self.admins_for(hotel)
      recipients = User.where(role: "superadmin").pluck(:email)
      recipients << hotel.salesperson.email if hotel.salesperson&.email.present? && !hotel.salesperson.email.end_with?(".local")
      recipients.compact_blank.map(&:downcase).uniq
    end

    def self.owners_for(hotel)
      hotel.user_hotel_accesses.active.joins(:role, :user)
           .where(roles: { slug: "hotel_owner" }).pluck("users.email")
           .compact_blank.map(&:downcase).uniq
    end
  end
end
