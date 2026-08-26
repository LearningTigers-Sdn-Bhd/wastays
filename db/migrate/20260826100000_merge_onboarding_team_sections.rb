# frozen_string_literal: true

# The Team phase had two onboarding sections: roles_permissions (a read-only
# review with one checkbox) and staff_setup (the draft staff table). They are one
# page now, so their rows become one row. HotelOnboardingSection validates
# section_key against the catalog, so leaving the old rows in place would make
# every in-flight hotel invalid.
class MergeOnboardingTeamSections < ActiveRecord::Migration[8.0]
  LEGACY_KEYS = %w[roles_permissions staff_setup].freeze
  NEW_KEY = "team_setup"
  RESOLVED = %w[complete skipped].freeze

  # The real model validates against the catalog, which no longer holds the keys
  # this migration has to read.
  class Section < ActiveRecord::Base
    self.table_name = "hotel_onboarding_sections"
  end

  class AuditEvent < ActiveRecord::Base
    self.table_name = "onboarding_audit_events"
  end

  def up
    Section.where(section_key: LEGACY_KEYS).group_by(&:hotel_id).each do |hotel_id, pair|
      by_key = pair.index_by(&:section_key)
      roles = by_key["roles_permissions"]
      staff = by_key["staff_setup"]

      Section.upsert(
        {
          hotel_id: hotel_id,
          section_key: NEW_KEY,
          state: merged_state(roles, staff),
          completed_at: pair.filter_map(&:completed_at).min,
          skipped_at: nil,
          decision_metadata: merged_metadata(roles, staff),
          created_at: pair.map(&:created_at).min,
          updated_at: Time.current
        },
        unique_by: %i[hotel_id section_key]
      )
    end

    AuditEvent.where(section_key: LEGACY_KEYS).update_all(section_key: NEW_KEY)
    Section.where(section_key: LEGACY_KEYS).delete_all
  end

  # The split cannot be rebuilt honestly: one row cannot say which half an owner
  # finished first. Rolling back gives both halves the merged state.
  def down
    Section.where(section_key: NEW_KEY).find_each do |section|
      LEGACY_KEYS.each do |key|
        Section.upsert(
          section.attributes.except("id").merge("section_key" => key, "updated_at" => Time.current),
          unique_by: %i[hotel_id section_key]
        )
      end
    end

    AuditEvent.where(section_key: NEW_KEY).update_all(section_key: "roles_permissions")
    Section.where(section_key: NEW_KEY).delete_all
  end

  private

  # The merged step is required, so it can never be skipped. "No additional
  # staff" was a skip before and is a completed decision now.
  def merged_state(roles, staff)
    states = [ roles, staff ].compact.map(&:state)
    return "needs_attention" if states.include?("needs_attention")
    return "complete" if states.size == LEGACY_KEYS.size && states.all? { |state| RESOLVED.include?(state) }
    return "in_progress" if states.any? { |state| state != "not_started" }

    "not_started"
  end

  # Readiness reads permission_fingerprint from the roles half and source from
  # the staff half. Both have to survive, under the merged step's own source.
  def merged_metadata(roles, staff)
    roles_metadata = roles&.decision_metadata || {}
    staff_metadata = staff&.decision_metadata || {}
    merged = roles_metadata.slice("confirmed_role_slugs", "permission_fingerprint")
                           .merge(staff_metadata.slice("staff_count", "decision"))
    merged["source"] = "team_setup" if staff_metadata["source"] == "staff_draft_setup" && merged["permission_fingerprint"].present?
    merged
  end
end
