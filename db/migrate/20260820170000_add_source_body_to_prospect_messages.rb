# frozen_string_literal: true

class AddSourceBodyToProspectMessages < ActiveRecord::Migration[8.0]
  def change
    # What the hotel's own code wrote, kept only when the reply stylist replaced
    # it. Null on every message the guest received exactly as Ruby composed it,
    # which is most of them -- so the column reads as "this was rewritten", and
    # staff looking at a thread in a language they do not speak have the English
    # the assistant actually computed.
    add_column :prospect_messages, :source_body, :text
  end
end
