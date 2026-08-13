# frozen_string_literal: true

module Onboarding
  class CreateDeliveries
    # Submitting only tells WAStays there is something to look at. Nobody outside
    # the property hears from us yet.
    def self.for_submission(submission)
      DeliveryRecipients.admins_for(submission.hotel).each do |email|
        create(submission, "admin_submitted", "User", nil, email:)
      end
    end

    # Staff and corporate contacts are invited once the property is actually
    # launched. Inviting them at submission meant a reviewer who requested changes
    # had already introduced people to a property that was not open, with no way
    # to take the mail back.
    def self.for_approval(submission)
      hotel = submission.hotel
      hotel.onboarding_staff_drafts.undelivered.find_each do |draft|
        create(submission, "staff_invitation", "OnboardingStaffDraft", draft.id)
      end
      hotel.onboarding_corporate_drafts.undelivered.find_each do |draft|
        create(submission, "corporate_invitation", "OnboardingCorporateDraft", draft.id)
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
