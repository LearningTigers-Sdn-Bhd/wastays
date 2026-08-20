# frozen_string_literal: true

class AddLanguageToConversations < ActiveRecord::Migration[8.0]
  def change
    # Nullable rather than defaulting "en", because "nobody has written a
    # sentence in this thread yet" and "this thread is in English" are different
    # facts and the reply stylist has to tell them apart: the first is a guess,
    # the second is something the guest established.
    add_column :conversations, :language, :string
  end
end
