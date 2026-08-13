# frozen_string_literal: true

module Onboarding
  class CreateDeliveries
    def self.for_submission(submission)
      hotel = submission.hotel
      hotel.onboarding_staff_drafts.undelivered.find_each do |draft|
        create(submission, "staff_invitation", "OnboardingStaffDraft", draft.id)
      end
      hotel.onboarding_corporate_drafts.undelivered.find_each do |draft|
        create(submission, "corporate_invitation", "OnboardingCorporateDraft", draft.id)
      end
      DeliveryRecipients.admins_for(hotel).each do |email|
        create(submission, "admin_submitted", "User", nil, email:)
      end
    end

    def self.for_owners(submission, type)
      DeliveryRecipients.owners_for(submission.hotel).each do |email|
        create(submission, type, "User", nil, email:)
      end
    end

    def self.create(submission, type, source_type, source_id, email: nil)
      identity = source_id || email
      submission.deliveries.find_or_create_by!(idempotency_key: [ submission.id, type, source_type, identity ].join(":")) do |delivery|
        delivery.delivery_type = type
        delivery.source_type = source_type
        delivery.source_id = source_id
        delivery.recipient_email = email
      end
    end

    private_class_method :create
  end
end
