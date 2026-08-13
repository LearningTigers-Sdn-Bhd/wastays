# frozen_string_literal: true

# Collapses the pre-onboarding hotel lifecycle onto the four canonical statuses.
#
# The five legacy setup statuses tracked how far an owner had got through the old
# wizard. `onboarding_sections` records that now, far more precisely, so nothing is
# lost by folding them all into `setup`. `approved` and `live` already meant the same
# thing and were read as a pair everywhere.
#
# `pre_suspension_status` holds a raw status stashed by the suspend/reactivate round
# trip, so it has to move too — otherwise reactivating a hotel suspended before this
# migration would restore a status that no longer exists.
class NormalizeHotelLifecycleStatuses < ActiveRecord::Migration[8.1]
  LEGACY_SETUP = %w[registered email_verified profile_incomplete rooms_incomplete inventory_incomplete].freeze

  def up
    %w[status pre_suspension_status].each do |column|
      report(column)

      execute(<<~SQL.squish)
        UPDATE hotels
        SET #{column} = 'setup'
        WHERE #{column} IN (#{LEGACY_SETUP.map { |s| connection.quote(s) }.join(', ')})
      SQL

      execute("UPDATE hotels SET #{column} = 'live' WHERE #{column} = 'approved'")
    end
  end

  # `live` cannot be told apart from a row that was already `live`, and the legacy
  # setup statuses carry nothing the onboarding progress does not.
  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def report(column)
    counts = select_all(<<~SQL.squish).to_a
      SELECT #{column} AS value, COUNT(*) AS total
      FROM hotels
      WHERE #{column} IN (#{(LEGACY_SETUP + %w[approved]).map { |s| connection.quote(s) }.join(', ')})
      GROUP BY #{column}
    SQL

    if counts.empty?
      say "hotels.#{column}: nothing to migrate"
    else
      counts.each { |row| say "hotels.#{column}: #{row['total']} row(s) on '#{row['value']}'" }
    end
  end
end
