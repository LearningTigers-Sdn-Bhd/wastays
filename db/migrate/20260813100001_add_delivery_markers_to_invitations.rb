# frozen_string_literal: true

# Two halves of the same idea: an invitation can now exist without having been
# emailed, and a staff draft can record which invitation it became.
#
# `last_sent_at` is what separates "waiting for the owner to send it" from
# "sitting in someone's inbox unanswered". Without it the staff page would show
# an expiry countdown for a message nobody ever received.
#
# The staff-draft columns mirror what onboarding_corporate_drafts already
# carries, so submission can be resumed after a partial failure without
# inviting anyone twice.
class AddDeliveryMarkersToInvitations < ActiveRecord::Migration[8.1]
  def up
    add_column :invitations, :last_sent_at, :datetime

    # Every invitation that exists today was created by a service that mailed as
    # it created, so its creation is its send.
    execute "UPDATE invitations SET last_sent_at = created_at WHERE last_sent_at IS NULL"

    add_reference :onboarding_staff_drafts, :invitation, foreign_key: true, index: true
    add_column :onboarding_staff_drafts, :delivered_at, :datetime
    add_index :onboarding_staff_drafts, :invitation_id,
              unique: true, where: "invitation_id IS NOT NULL",
              name: "index_onboarding_staff_drafts_on_delivered_invitation"
  end

  def down
    remove_index :onboarding_staff_drafts, name: "index_onboarding_staff_drafts_on_delivered_invitation"
    remove_column :onboarding_staff_drafts, :delivered_at
    remove_reference :onboarding_staff_drafts, :invitation, foreign_key: true
    remove_column :invitations, :last_sent_at
  end
end
