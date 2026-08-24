# frozen_string_literal: true

# The tool-calling loop is now the only way a concierge turn runs, so there is
# no longer a second pipeline for this flag to choose between.
#
# It shipped off everywhere so the loop could be rolled out one hotel at a time
# against that hotel's own baseline. What actually settled the question was the
# eval harness: every conversation fixture ran through both pipelines under the
# same assertions, and the interpreting one has now been deleted.
#
# Irreversible on purpose. `down` restores the column, but the code that read it
# is gone, so a rollback would give every hotel a switch wired to nothing.
class DropAgentLoopFlagFromHotels < ActiveRecord::Migration[8.1]
  def up
    remove_column :hotels, :ai_concierge_agent_loop_enabled
  end

  def down
    add_column :hotels, :ai_concierge_agent_loop_enabled, :boolean, default: true, null: false
  end
end
