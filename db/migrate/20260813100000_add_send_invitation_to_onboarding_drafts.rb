# frozen_string_literal: true

# Whether submission should email this draft, or keep the person queued for the
# owner to invite from the live portal later.
#
# Default false, deliberately. An owner filling in a setup table is describing
# their team, not asking us to contact anyone yet; sending has to be the thing
# they opt into, not the thing they remember to switch off.
class AddSendInvitationToOnboardingDrafts < ActiveRecord::Migration[8.1]
  def change
    add_column :onboarding_staff_drafts, :send_invitation, :boolean, null: false, default: false
    add_column :onboarding_corporate_drafts, :send_invitation, :boolean, null: false, default: false
  end
end
