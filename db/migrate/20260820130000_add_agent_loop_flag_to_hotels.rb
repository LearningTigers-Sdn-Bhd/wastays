# frozen_string_literal: true

class AddAgentLoopFlagToHotels < ActiveRecord::Migration[8.0]
  def change
    # Off everywhere. The tool-calling loop is rolled out one hotel at a time,
    # against that hotel's own answer_mode baseline in hotel_knowledge_diagnostics.
    add_column :hotels, :ai_concierge_agent_loop_enabled, :boolean, default: false, null: false
  end
end
