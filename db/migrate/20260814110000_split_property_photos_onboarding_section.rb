# frozen_string_literal: true

# Property photos moved out of the property profile step into a step of their
# own. A hotel that had already finished the profile step necessarily had a
# featured photo — the old step would not complete without one — so the new
# section starts out complete for them rather than sending them back a step.
#
# Hotels still working through the profile step get the section in its default
# not_started state, which InitializeProgress creates on their next visit.
class SplitPropertyPhotosOnboardingSection < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL.squish)
      INSERT INTO hotel_onboarding_sections (hotel_id, section_key, state, decision_metadata, completed_at, created_at, updated_at)
      SELECT hotels.id, 'property_photos', 'complete', '{"source":"property_photos_backfill"}'::jsonb, NOW(), NOW(), NOW()
      FROM hotels
      WHERE hotels.featured_photo_attachment_id IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM hotel_onboarding_sections existing
          WHERE existing.hotel_id = hotels.id
            AND existing.section_key = 'property_profile'
            AND existing.state = 'complete'
        )
        AND NOT EXISTS (
          SELECT 1 FROM hotel_onboarding_sections existing
          WHERE existing.hotel_id = hotels.id
            AND existing.section_key = 'property_photos'
        )
    SQL
  end

  def down
    execute("DELETE FROM hotel_onboarding_sections WHERE section_key = 'property_photos'")
  end
end
