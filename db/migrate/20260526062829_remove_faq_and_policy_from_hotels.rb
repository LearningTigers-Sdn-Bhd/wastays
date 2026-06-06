# frozen_string_literal: true

class RemoveFaqAndPolicyFromHotels < ActiveRecord::Migration[8.0]
  def change
    remove_column :hotels, :faq, :jsonb
    remove_column :hotels, :policy, :jsonb
  end
end
