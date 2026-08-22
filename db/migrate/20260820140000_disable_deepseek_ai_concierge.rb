# frozen_string_literal: true

# DeepSeek has been dropped as a concierge provider. Nothing in this codebase
# ever confirmed it supports structured output or tool calling, so it was the
# one provider the agent loop had to route around, via a single-hop JSON path
# with no test coverage of its own.
#
# A hotel still holding the value would now fail validation on any save and
# raise a KeyError from `ai_concierge_model_name`. Repointing it at another
# provider would be worse than useless -- its stored key is a DeepSeek key, so
# the concierge would keep answering guests with a config that authenticates
# nowhere. So it is switched off instead, and someone chooses a provider
# deliberately.
#
# The key itself is kept: it is encrypted, harmless, and its presence is the
# only remaining sign that this property had the concierge configured at all.
class DisableDeepseekAiConcierge < ActiveRecord::Migration[8.1]
  # Written as SQL rather than `Hotel.find_each(&:save)` on purpose. By the
  # time this runs, "deepseek" is no longer in the enum, so loading these rows
  # as models and saving them fails validation on the very records the
  # migration exists to repair.
  def up
    execute(<<~SQL.squish)
      UPDATE hotels
      SET ai_provider_enabled = FALSE,
          ai_provider_name = NULL
      WHERE ai_provider_name = 'deepseek'
    SQL
  end

  def down
    # Irreversible by design: the provider it would restore no longer exists in
    # the enum, so re-selecting it would leave the row invalid again.
  end
end
