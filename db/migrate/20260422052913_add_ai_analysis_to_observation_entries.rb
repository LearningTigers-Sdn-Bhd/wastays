class AddAiAnalysisToObservationEntries < ActiveRecord::Migration[8.0]
  def change
    add_column :observation_entries, :ai_analysis, :jsonb
  end
end
