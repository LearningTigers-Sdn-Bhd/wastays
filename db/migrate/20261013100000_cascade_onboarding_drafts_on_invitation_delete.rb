# frozen_string_literal: true

# A delivered onboarding draft points at the invitation it created. Without a
# delete rule, Postgres refuses to delete that invitation, so revoking it, or
# adding the person directly through Add Staff (which cancels their
# outstanding invitation), failed with a foreign-key violation.
#
# Cascade rather than nullify: a draft with no invitation counts as undelivered,
# and Onboarding::DeliverInvitations would invite the revoked person again.
class CascadeOnboardingDraftsOnInvitationDelete < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :onboarding_staff_drafts, :invitations
    add_foreign_key :onboarding_staff_drafts, :invitations, on_delete: :cascade

    remove_foreign_key :onboarding_corporate_drafts, :invitations
    add_foreign_key :onboarding_corporate_drafts, :invitations, on_delete: :cascade
  end
end
